require 'net/http'
require 'json'

module EmailCampaigns
  module Dns
    # Resolves each DNS record an EmailSenderIdentity expects and reports, per record,
    # whether it is actually published and matches what SES expects. This gives the user
    # a live, per-record diagnostic instead of SES's coarse PENDING/SUCCESS status — SES
    # never says which record is wrong. Gem-free: queries a public DNS-over-HTTPS resolver
    # (same path the app already uses for outbound HTTPS), so it works even where UDP/53
    # is restricted. Returns each expected record annotated with status: ok | missing | mismatch.
    class RecordChecker
      DOH_URL = 'https://dns.google/resolve'.freeze
      TIMEOUT = 4

      def initialize(identity)
        @identity = identity
      end

      def perform
        expected_records.map { |record| check(record) }
      end

      private

      def expected_records
        records = (@identity.dkim_records || []).map do |record|
          { 'kind' => 'dkim', 'type' => 'CNAME', 'name' => record['name'], 'value' => record['value'], 'required' => true }
        end
        if @identity.spf_record.present?
          records << { 'kind' => 'spf', 'type' => 'TXT', 'name' => @identity.domain, 'value' => @identity.spf_record, 'required' => false }
        end
        if @identity.dmarc_record.present?
          records << { 'kind' => 'dmarc', 'type' => 'TXT', 'name' => "_dmarc.#{@identity.domain}", 'value' => @identity.dmarc_record, 'required' => false }
        end
        records
      end

      def check(record)
        answers = resolve(record['name'], record['type'])
        record.merge('found' => answers.first, 'status' => status_for(record, answers))
      end

      def status_for(record, answers)
        return 'missing' if answers.empty?

        matches?(record, answers) ? 'ok' : 'mismatch'
      end

      def matches?(record, answers)
        case record['kind']
        when 'dkim'
          answers.any? { |answer| clean(answer) == clean(record['value']) }
        when 'spf'
          answers.any? { |answer| clean(answer).include?('include:amazonses.com') }
        when 'dmarc'
          answers.any? { |answer| clean(answer).start_with?('v=dmarc1') }
        else
          false
        end
      end

      # Strips surrounding quotes (DoH wraps TXT in quotes), trailing dots (CNAME targets),
      # whitespace and case so comparisons are robust.
      def clean(value)
        value.to_s.delete('"').strip.chomp('.').downcase
      end

      def resolve(name, type)
        uri = URI("#{DOH_URL}?name=#{ERB::Util.url_encode(name)}&type=#{type}")
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
          http.get(uri.request_uri, 'accept' => 'application/dns-json')
        end
        return [] unless response.code.to_i == 200

        Array(JSON.parse(response.body)['Answer']).map { |answer| answer['data'].to_s }
      rescue StandardError
        []
      end
    end
  end
end
