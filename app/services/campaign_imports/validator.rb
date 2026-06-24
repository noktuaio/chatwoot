require 'stringio'

module CampaignImports
  class Validator
    NORMALIZED_HEADERS = %w[row_number name phone_number phone_hash batch_index].freeze
    ERROR_HEADERS = %w[row_number name phone_number errors].freeze

    def initialize(campaign_import)
      @campaign_import = campaign_import
    end

    def perform
      campaign_import.update!(status: :validating)
      parsed_file = Parser.new(campaign_import.original_file, filename: campaign_import.source_filename).perform
      validate_parsed_file(parsed_file)
    rescue StandardError => e
      mark_validation_failed(['file_could_not_be_processed'], [], exception: e)
    end

    private

    attr_reader :campaign_import

    def validate_parsed_file(parsed_file)
      unsupported_format = !CampaignImports::Config.supported_formats.include?(parsed_file.format)
      return mark_validation_failed(['unsupported_file_format'], []) if unsupported_format

      header_result = HeaderMapper.new(parsed_file.headers).perform
      data_rows = parsed_file.rows.reject { |row| row.values.all? { |value| value.to_s.strip.empty? } }
      global_errors = header_result.errors
      global_errors << 'empty_file' if data_rows.blank?
      global_errors << 'row_limit_exceeded' if row_limit_exceeded?(parsed_file.format, data_rows.size)

      row_results = build_row_results(data_rows, header_result.mapping)
      add_duplicate_errors(row_results)
      global_errors << 'batch_count_exceeds_rows' if campaign_import.batch_count.to_i > data_rows.size && data_rows.present?
      global_errors << 'too_many_batches' if campaign_import.batch_count.to_i > CampaignImports::Config.max_batches

      return mark_validation_failed(global_errors, row_results) if global_errors.present? || row_results.any? { |row| row[:errors].present? }

      mark_ready(row_results)
    end

    def build_row_results(rows, mapping)
      rows.map do |row|
        name = value_at(row, mapping[:name])
        phone = value_at(row, mapping[:phone_number])
        errors = formula_errors(row, mapping)
        errors << 'blank_name' if name.blank?

        normalized = normalize_phone(phone, errors)

        {
          row_number: row.row_number,
          raw_name: name,
          raw_phone: phone,
          raw_phone_masked: normalized&.masked || PhoneNormalizer.mask_raw(phone),
          normalized_name: name.squish,
          normalized_phone: normalized&.phone_number,
          normalized_phone_hash: normalized&.hash,
          errors: errors.compact
        }
      end
    end

    def formula_errors(row, mapping)
      row.values.each_with_index.filter_map do |value, index|
        next unless CsvSanitizer.formula_like?(value, allow_phone_plus: index == mapping[:phone_number])

        'formula_detected'
      end.uniq
    end

    def normalize_phone(phone, errors)
      PhoneNormalizer.normalize!(phone)
    rescue PhoneNormalizer::Error => e
      errors << e.message
      nil
    end

    def add_duplicate_errors(row_results)
      grouped = row_results.select { |row| row[:normalized_phone_hash].present? }
                           .group_by { |row| row[:normalized_phone_hash] }
      grouped.each_value do |rows|
        next if rows.one?

        rows.each { |row| row[:errors] << 'duplicate_phone_in_file' }
      end
    end

    def mark_ready(row_results)
      plan = nil
      ActiveRecord::Base.transaction do
        reset_validation_rows!
        persist_rows(row_results)
        plan = LabelPlanner.new(campaign_import, total_rows: row_results.size).perform
        attach_normalized_csv(row_results, plan)
        attach_report_csv(row_results, plan, status: 'ready_to_confirm')
        campaign_import.update!(
          status: :ready_to_confirm,
          total_rows: row_results.size,
          valid_rows: row_results.size,
          invalid_rows: 0,
          validated_at: Time.current,
          validation_summary: {
            errors: {},
            warnings: validation_warnings(plan)
          }
        )
      end
    end

    def mark_validation_failed(global_errors, row_results, exception: nil)
      ActiveRecord::Base.transaction do
        reset_validation_rows!
        persist_rows(row_results)
        attach_error_csv(global_errors, row_results)
        campaign_import.update!(
          status: :validation_failed,
          total_rows: row_results.size,
          valid_rows: row_results.count { |row| row[:errors].blank? },
          invalid_rows: row_results.count { |row| row[:errors].present? },
          validated_at: Time.current,
          validation_summary: validation_summary(global_errors, row_results, exception)
        )
      end
    end

    def reset_validation_rows!
      campaign_import.campaign_import_rows.destroy_all
      campaign_import.campaign_import_labels.destroy_all
      campaign_import.normalized_csv.purge if campaign_import.normalized_csv.attached?
      campaign_import.error_csv.purge if campaign_import.error_csv.attached?
      campaign_import.report_csv.purge if campaign_import.report_csv.attached?
    end

    def persist_rows(row_results)
      row_results.each do |row|
        campaign_import.campaign_import_rows.create!(
          row_number: row[:row_number],
          raw_name: row[:raw_name],
          raw_phone_masked: row[:raw_phone_masked],
          normalized_name: row[:errors].blank? ? row[:normalized_name] : nil,
          normalized_phone_hash: row[:errors].blank? ? row[:normalized_phone_hash] : nil,
          batch_index: row[:batch_index],
          status: row[:errors].blank? ? :valid : :invalid,
          error_messages: row[:errors]
        )
      end
    end

    def attach_normalized_csv(row_results, plan)
      rows = row_results.map.with_index do |row, index|
        row[:batch_index] = plan.batch_indexes[index]
        {
          'row_number' => row[:row_number],
          'name' => row[:normalized_name],
          'phone_number' => row[:normalized_phone],
          'phone_hash' => row[:normalized_phone_hash],
          'batch_index' => row[:batch_index]
        }
      end

      campaign_import.normalized_csv.attach(
        io: StringIO.new(CsvSanitizer.generate(NORMALIZED_HEADERS, rows)),
        filename: normalized_filename('normalized'),
        content_type: 'text/csv'
      )
      campaign_import.campaign_import_rows.each do |import_row|
        source = row_results.find { |row| row[:row_number] == import_row.row_number }
        import_row.update!(batch_index: source[:batch_index])
      end
    end

    def attach_error_csv(global_errors, row_results)
      rows = row_results.select { |row| row[:errors].present? }.map do |row|
        {
          'row_number' => row[:row_number],
          'name' => row[:raw_name],
          'phone_number' => row[:raw_phone_masked],
          'errors' => row[:errors].join(';')
        }
      end
      rows << { 'row_number' => '', 'name' => '', 'phone_number' => '', 'errors' => global_errors.join(';') } if global_errors.present?

      campaign_import.error_csv.attach(
        io: StringIO.new(CsvSanitizer.generate(ERROR_HEADERS, rows)),
        filename: normalized_filename('errors'),
        content_type: 'text/csv'
      )
    end

    def attach_report_csv(row_results, plan, status:)
      rows = [
        { 'metric' => 'status', 'value' => status },
        { 'metric' => 'total_rows', 'value' => row_results.size },
        { 'metric' => 'base_label', 'value' => plan.base_label },
        { 'metric' => 'batch_count', 'value' => plan.batch_sizes.size }
      ]

      campaign_import.report_csv.attach(
        io: StringIO.new(CsvSanitizer.generate(%w[metric value], rows)),
        filename: normalized_filename('report'),
        content_type: 'text/csv'
      )
    end

    def validation_summary(global_errors, row_results, exception)
      row_errors = row_results.flat_map { |row| row[:errors] }
      {
        errors: (global_errors + row_errors).compact.tally,
        exception_class: exception&.class&.name
      }.compact
    end

    def validation_warnings(plan)
      warnings = []
      warnings << 'large_batch_count' if plan.batch_sizes.size > CampaignImports::Config.warn_batches_above
      warnings
    end

    def value_at(row, index)
      return '' if index.nil?

      row.values[index].to_s.strip
    end

    def row_limit_exceeded?(format, row_count)
      limit = format == 'xlsx' ? CampaignImports::Config.max_xlsx_rows : CampaignImports::Config.max_csv_rows
      row_count > limit
    end

    def normalized_filename(suffix)
      basename = campaign_import.source_filename.to_s.sub(/\.[^.]*\z/, '').presence || "campaign_import_#{campaign_import.id}"
      "#{basename}_#{suffix}.csv"
    end
  end
end
