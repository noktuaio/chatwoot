module EmailCampaigns
  class RecipientImporter
    Error = Class.new(StandardError)
    Result = Struct.new(:imported, :duplicates, :invalid, :suppressed, :total, keyword_init: true)

    MAX_ROWS = 50_000

    def initialize(campaign, file, filename:)
      @campaign = campaign
      @file = file
      @filename = filename
      @account = campaign.account
    end

    def perform
      parsed = CampaignImports::Parser.new(@file, filename: @filename).perform
      raise Error, 'unsupported_file_format' unless CampaignImports::Config.supported_formats.include?(parsed.format)

      mapper = header_mapping(parsed.headers)
      rows = data_rows(parsed)
      raise Error, 'empty_file' if rows.blank?
      raise Error, 'row_limit_exceeded' if rows.size > MAX_ROWS

      import_rows(rows, mapper)
    end

    private

    def header_mapping(headers)
      result = CampaignImports::HeaderMapper.new(headers, mode: :email).perform
      raise Error, result.errors.join(',') if result.errors.present?

      result
    end

    def data_rows(parsed)
      parsed.rows.reject { |row| row.values.all? { |v| v.to_s.strip.empty? } }
    end

    def import_rows(rows, mapper)
      suppressed = EmailSuppression.suppressed_set_for(@account)
      seen = Set.new
      stats = { imported: 0, duplicates: 0, invalid: 0, suppressed: 0 }

      ActiveRecord::Base.transaction do
        rows.each { |row| process_row(row, mapper, suppressed, seen, stats) }
        @campaign.refresh_counters!
      end

      Result.new(total: rows.size, **stats)
    end

    def process_row(row, mapper, suppressed, seen, stats)
      name = value_at(row, mapper.mapping[:name])
      raw_email = value_at(row, mapper.mapping[:email])
      normalized = EmailCampaigns::EmailNormalizer.normalize!(raw_email)
      email = normalized.email

      return (stats[:duplicates] += 1) if seen.include?(email) || existing?(email)

      seen << email
      is_suppressed = suppressed.include?(email)
      stats[is_suppressed ? :suppressed : :imported] += 1
      @campaign.email_campaign_recipients.create!(
        name: name.presence, email: email, status: is_suppressed ? :suppressed : :pending,
        custom_data: custom_data_for(row, mapper.extra_columns)
      )
    rescue EmailCampaigns::EmailNormalizer::Error
      stats[:invalid] += 1
    rescue ActiveRecord::RecordInvalid
      # A row that fails persistence (e.g. name > 255 chars hitting the global
      # 255 validation) must count as invalid without aborting the whole import.
      # Roll back the optimistic counter + seen-claim made before create!.
      stats[:invalid] += 1
      stats[is_suppressed ? :suppressed : :imported] -= 1 unless is_suppressed.nil?
      seen.delete(email) unless email.nil?
    end

    def custom_data_for(row, extra_columns)
      extra_columns.transform_values { |index| value_at(row, index) }
    end

    def existing?(email)
      @campaign.email_campaign_recipients.where('lower(email) = ?', email).exists?
    end

    def value_at(row, index)
      return '' if index.nil?

      row.values[index].to_s.strip
    end
  end
end
