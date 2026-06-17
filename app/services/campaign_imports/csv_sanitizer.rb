require 'csv'

module CampaignImports
  class CsvSanitizer
    SPREADSHEET_FORMULA_PREFIX = /\A[=+\-@]/.freeze
    UPLOAD_FORMULA_PREFIX = /\A[=\-@]/.freeze

    class << self
      def formula_like?(value, allow_phone_plus: false)
        string = value.to_s.sub(/\A[[:space:]]+/, '')
        return false if string.empty?
        return false if allow_phone_plus && string.match?(/\A\+\d[\d\s().-]*\z/)

        string.match?(UPLOAD_FORMULA_PREFIX) || string.match?(/\A\+(?!\d)/)
      end

      def safe_cell(value)
        string = value.to_s
        stripped = string.sub(/\A[[:space:]]+/, '')
        return string unless stripped.match?(SPREADSHEET_FORMULA_PREFIX)

        "'#{string}"
      end

      def generate(headers, rows)
        CSV.generate(headers: headers, write_headers: true) do |csv|
          rows.each do |row|
            csv << headers.map { |header| safe_cell(row[header]) }
          end
        end
      end
    end
  end
end
