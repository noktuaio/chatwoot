require 'csv'
require 'stringio'

module CampaignImports
  class Importer
    Error = Class.new(StandardError)

    def initialize(campaign_import)
      @campaign_import = campaign_import
      @account = campaign_import.account
    end

    def perform
      return unless transition_to_importing!

      imported_count = 0
      existing_count = 0

      with_suppressed_contact_events do
        ActiveRecord::Base.transaction do
          label_records = ensure_labels!

          normalized_rows.each do |row|
            contact = account.contacts.find_by(phone_number: row[:phone_number])
            was_existing = contact.present?
            contact ||= account.contacts.create!(name: row[:name], phone_number: row[:phone_number])
            contact.update!(name: row[:name]) if contact.name.blank? && row[:name].present?
            apply_labels!(contact, label_records[:base], label_records[:batches].fetch(row[:batch_index]))
            mark_row_imported!(row, contact, was_existing, label_records)

            imported_count += 1
            existing_count += 1 if was_existing
          end

          update_label_counts!
          attach_report_csv(imported_count, existing_count)
          campaign_import.update!(
            status: :completed,
            imported_contacts_count: imported_count,
            existing_contacts_count: existing_count,
            failed_contacts_count: 0,
            import_finished_at: Time.current
          )
        end
      end
    rescue StandardError => e
      campaign_import.update!(
        status: :failed,
        failed_contacts_count: campaign_import.valid_rows,
        import_finished_at: Time.current,
        validation_summary: campaign_import.validation_summary.to_h.merge(import_error: e.class.name)
      )
    end

    private

    attr_reader :campaign_import, :account

    def transition_to_importing!
      should_import = false
      campaign_import.with_lock do
        campaign_import.reload
        next if campaign_import.importing? || campaign_import.completed? || campaign_import.completed_with_failures?

        raise Error, 'campaign_import_not_ready' unless campaign_import.queued? || campaign_import.ready_to_confirm?

        campaign_import.update!(status: :importing, import_started_at: Time.current)
        should_import = true
      end
      should_import
    end

    def with_suppressed_contact_events
      previous = Current.suppress_contact_events
      Current.suppress_contact_events = true
      yield
    ensure
      Current.suppress_contact_events = previous
    end

    def ensure_labels!
      base_import_label = campaign_import.campaign_import_labels.kind_base.first!
      batch_import_labels = campaign_import.campaign_import_labels.kind_batch.index_by(&:batch_index)

      base_label = ensure_label_record!(base_import_label)
      batch_labels = batch_import_labels.transform_values { |import_label| ensure_label_record!(import_label) }
      { base: base_label, batches: batch_labels }
    end

    def ensure_label_record!(campaign_import_label)
      label = account.labels.find_or_initialize_by(title: campaign_import_label.title)
      raise Error, 'label_collision_visible_on_sidebar' if label.persisted? && label.show_on_sidebar?

      label.assign_attributes(show_on_sidebar: false) unless label.persisted?
      label.save!
      campaign_import_label.update!(label_id: label.id)
      label
    end

    def normalized_rows
      @normalized_rows ||= begin
        raise Error, 'normalized_csv_missing' unless campaign_import.normalized_csv.attached?

        csv_data = campaign_import.normalized_csv.download
        CSV.parse(csv_data, headers: true).map do |row|
          normalized = PhoneNormalizer.normalize!(row['phone_number'])
          {
            row_number: row['row_number'].to_i,
            name: row['name'].to_s.strip,
            phone_number: normalized.phone_number,
            phone_hash: normalized.hash,
            batch_index: row['batch_index'].to_i
          }
        end
      end
    end

    def apply_labels!(contact, base_label, batch_label)
      contact.label_list.add(base_label.title)
      contact.label_list.add(batch_label.title)
      contact.save!
    end

    def mark_row_imported!(row, contact, was_existing, label_records)
      import_row = campaign_import.campaign_import_rows.find_by!(row_number: row[:row_number])
      applied_labels = [
        label_records[:base].title,
        label_records[:batches].fetch(row[:batch_index]).title
      ]
      import_row.update!(
        contact_id: contact.id,
        was_existing_contact: was_existing,
        labels_applied: applied_labels,
        batch_index: row[:batch_index],
        status: :imported
      )
    end

    def update_label_counts!
      campaign_import.campaign_import_labels.find_each do |import_label|
        count = if import_label.kind_base?
                  campaign_import.campaign_import_rows.status_imported.count
                else
                  campaign_import.campaign_import_rows.status_imported.where(batch_index: import_label.batch_index).count
                end
        import_label.update!(applied_count: count)
      end
    end

    def attach_report_csv(imported_count, existing_count)
      rows = [
        { 'metric' => 'status', 'value' => 'completed' },
        { 'metric' => 'imported_contacts_count', 'value' => imported_count },
        { 'metric' => 'existing_contacts_count', 'value' => existing_count },
        { 'metric' => 'created_contacts_count', 'value' => imported_count - existing_count },
        { 'metric' => 'base_label', 'value' => campaign_import.base_label },
        { 'metric' => 'batch_count', 'value' => campaign_import.batch_count }
      ]

      campaign_import.report_csv.attach(
        io: StringIO.new(CsvSanitizer.generate(%w[metric value], rows)),
        filename: report_filename,
        content_type: 'text/csv'
      )
    end

    def report_filename
      basename = campaign_import.source_filename.to_s.sub(/\.[^.]*\z/, '').presence || "campaign_import_#{campaign_import.id}"
      "#{basename}_report.csv"
    end
  end
end
