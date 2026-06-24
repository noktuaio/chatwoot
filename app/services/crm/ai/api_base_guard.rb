require 'ipaddr'
require 'resolv'
require 'uri'

module Crm
  module Ai
    # SSRF guard for an account-controlled AI `api_base`. Single source of truth used by every
    # client that lets a tenant point the OpenAI-compatible base at a custom host
    # (Crm::Ai::ResponsesClient + Autonomia::Agents::EmbeddingService). Enforces HTTPS-only, no
    # userinfo/query/fragment, and blocks localhost / private / link-local / loopback /
    # cloud-metadata ranges BOTH on the literal host and on the DNS-resolved address.
    module ApiBaseGuard
      class BlockedError < StandardError; end

      BLOCKED_HOSTS = %w[localhost localhost.localdomain].freeze
      BLOCKED_IP_RANGES = [
        IPAddr.new('0.0.0.0/8'),
        IPAddr.new('10.0.0.0/8'),
        IPAddr.new('100.64.0.0/10'),
        IPAddr.new('127.0.0.0/8'),
        IPAddr.new('169.254.0.0/16'),
        IPAddr.new('172.16.0.0/12'),
        IPAddr.new('192.168.0.0/16'),
        IPAddr.new('::/128'),
        IPAddr.new('::1/128'),
        IPAddr.new('fc00::/7'),
        IPAddr.new('fe80::/10')
      ].freeze

      module_function

      # Validates `base` (a URL string). Returns the normalized base (trimmed, no trailing slash) on
      # success; raises BlockedError otherwise. Caller maps BlockedError to its own error type.
      def validate!(base)
        normalized = base.to_s.strip.chomp('/')
        uri = URI.parse(normalized)
        raise BlockedError, 'invalid_api_base' unless uri.is_a?(URI::HTTPS)
        raise BlockedError, 'invalid_api_base' if uri.host.blank? || uri.userinfo.present? || uri.query.present? || uri.fragment.present?
        raise BlockedError, 'invalid_api_base' if blocked_host?(uri.host)
        raise BlockedError, 'invalid_api_base' if blocked_resolved_host?(uri.host)

        normalized
      rescue URI::InvalidURIError
        raise BlockedError, 'invalid_api_base'
      end

      # true when `base` is safe; never raises. Convenience for callers that prefer a boolean.
      def safe?(base)
        validate!(base)
        true
      rescue BlockedError
        false
      end

      def blocked_host?(host)
        normalized_host = normalize_host(host)
        return true if BLOCKED_HOSTS.include?(normalized_host) || normalized_host.end_with?('.localhost')

        blocked_ip_address?(normalized_host)
      end

      def blocked_resolved_host?(host)
        normalized_host = normalize_host(host)
        return false if ip_address?(normalized_host)

        addresses = Resolv.getaddresses(normalized_host)
        return true if addresses.empty?

        addresses.any? { |address| blocked_ip_address?(address, reject_invalid: true) }
      rescue Resolv::ResolvError, ArgumentError
        true
      end

      def normalize_host(host)
        host.to_s.downcase.delete_suffix('.')
      end

      def ip_address?(address)
        IPAddr.new(address)
        true
      rescue IPAddr::InvalidAddressError
        false
      end

      def blocked_ip_address?(address, reject_invalid: false)
        ip = IPAddr.new(address)
        ip = ip.native if ip.respond_to?(:ipv4_mapped?) && ip.ipv4_mapped?
        BLOCKED_IP_RANGES.any? { |range| range.include?(ip) }
      rescue IPAddr::InvalidAddressError
        reject_invalid
      end
    end
  end
end
