require 'ipaddr'
require 'resolv'

module Crm
  module Ai
    class ResponsesClient
      class Error < StandardError; end

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

      def initialize(credential:)
        @credential = credential
      end

      def create(model:, instructions:, input:, schema: nil, reasoning_effort: 'low', tools: nil)
        body = base_body(model, instructions, input, schema, reasoning_effort, tools).merge(store: false)
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = post_responses(body, timeout: 120)
        parse_response(response, model: model, requested_tools: tools, started_at: started_at)
      end

      # Background mode: a OpenAI aceita o pedido e processa do lado dela; retorna na hora um
      # response_id que buscamos depois com retrieve. EXIGE store:true (a resposta fica retida
      # p/ ser recuperada). Usado pela geração de e-mail (operação de vários minutos).
      def create_background(model:, instructions:, input:, schema: nil, reasoning_effort: 'low', tools: nil)
        body = base_body(model, instructions, input, schema, reasoning_effort, tools).merge(store: true, background: true)
        response = post_responses(body, timeout: 120)
        payload = parse_raw(response)
        { id: payload['id'], status: payload['status'] }
      end

      # Consulta o estado de um pedido em background. status ∈ queued/in_progress/completed/
      # failed/incomplete/cancelled. Quando completed devolve o texto; senão devolve o erro.
      def retrieve(response_id)
        response = with_timeout_guard do
          HTTParty.get("#{api_base}/v1/responses/#{response_id}", headers: auth_headers, timeout: 30)
        end
        payload = parse_raw(response)
        {
          status: payload['status'],
          text: payload['output_text'].presence || extract_output_text(payload),
          error: payload.dig('error', 'message') || payload.dig('incomplete_details', 'reason')
        }
      end

      # Best-effort: apaga a resposta retida na OpenAI após persistirmos (minimiza retenção).
      def delete(response_id)
        with_timeout_guard do
          HTTParty.delete("#{api_base}/v1/responses/#{response_id}", headers: auth_headers, timeout: 30)
        end
        true
      rescue Error
        false
      end

      private

      def base_body(model, instructions, input, schema, reasoning_effort, tools = nil)
        body = {
          model: model,
          instructions: instructions,
          input: normalize_input(input),
          reasoning: { effort: reasoning_effort }
        }
        body[:text] = structured_text_format(schema) if schema.present?
        body[:tools] = tools if tools.present?
        body
      end

      def auth_headers
        { 'Authorization' => "Bearer #{@credential[:api_key]}", 'Content-Type' => 'application/json' }
      end

      def post_responses(body, timeout:)
        with_timeout_guard do
          HTTParty.post("#{api_base}/v1/responses", headers: auth_headers, body: body.to_json, timeout: timeout)
        end
      end

      # Encapsula timeouts de rede como Error (antes vazavam como Net::ReadTimeout → HTTP 500 cru
      # no controller, que só rescue-ava Error). Agora o chamador trata graciosamente.
      def with_timeout_guard
        yield
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT, SocketError => e
        raise Error, "network_timeout: #{e.class.name.demodulize.underscore}"
      end

      def parse_raw(response)
        raise Error, extract_error_message(response) unless response.success?

        response.parsed_response
      end

      # Back-compat: String callers (followup/summary/classify/rewrite) keep working — a plain
      # string is wrapped as a single user text part. Arrays (multimodal content parts / messages)
      # are passed through untouched.
      def normalize_input(input)
        return input unless input.is_a?(String)

        [{ role: 'user', content: [{ type: 'input_text', text: input }] }]
      end

      def api_base
        base = (@credential[:api_base].presence || 'https://api.openai.com').to_s.strip.chomp('/')
        validate_api_base!(base)
        base
      end

      def validate_api_base!(base)
        uri = URI.parse(base)
        raise Error, 'invalid_api_base' unless uri.is_a?(URI::HTTPS)
        raise Error, 'invalid_api_base' if uri.host.blank? || uri.userinfo.present? || uri.query.present? || uri.fragment.present?
        raise Error, 'invalid_api_base' if blocked_api_host?(uri.host)
        raise Error, 'invalid_api_base' if blocked_resolved_api_host?(uri.host)
      rescue URI::InvalidURIError
        raise Error, 'invalid_api_base'
      end

      def blocked_api_host?(host)
        normalized_host = normalize_api_host(host)
        return true if BLOCKED_HOSTS.include?(normalized_host) || normalized_host.end_with?('.localhost')

        blocked_ip_address?(normalized_host)
      end

      def blocked_resolved_api_host?(host)
        normalized_host = normalize_api_host(host)
        return false if ip_address?(normalized_host)

        addresses = Resolv.getaddresses(normalized_host)
        return true if addresses.empty?

        addresses.any? { |address| blocked_ip_address?(address, reject_invalid: true) }
      rescue Resolv::ResolvError, ArgumentError
        true
      end

      def normalize_api_host(host)
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

      def structured_text_format(schema)
        {
          format: {
            type: 'json_schema',
            name: schema[:name] || 'crm_ai_response',
            strict: true,
            schema: schema[:schema]
          }
        }
      end

      def parse_response(response, model: nil, requested_tools: nil, started_at: nil)
        unless response.success?
          raise Error, extract_error_message(response)
        end

        payload = response.parsed_response
        text = payload['output_text'].presence || extract_output_text(payload)
        raise Error, 'empty_response' if text.blank?

        used = tools_used(payload)
        log_call(model, requested_tools, used, started_at)
        {
          text: text,
          usage: payload['usage'] || {},
          response_id: payload['id'],
          tools_used: used
        }
      end

      # Tipos de item de output que representam uso de ferramenta (sufixo _call). SÓ metadados —
      # nunca conteúdo/args. Ex.: web_search_call → web_search, file_search_call → file_search.
      def tools_used(payload)
        Array(payload['output']).filter_map do |item|
          type = item['type'].to_s
          type.delete_suffix('_call') if type.end_with?('_call')
        end.uniq
      end

      # 1 log por chamada: modelo, tools pedidas, tools usadas, latência. NUNCA prompt/conteúdo/
      # credencial (só metadados — auditoria de uso de web_search etc.).
      def log_call(model, requested_tools, used, started_at)
        latency = started_at ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round : nil
        requested = Array(requested_tools).filter_map { |t| t.is_a?(Hash) ? (t[:type] || t['type']) : t }
        Rails.logger.info(
          "[crm][ai][responses] model=#{model} tools_requested=#{requested.join(',')} " \
          "tools_used=#{used.join(',')} latency_ms=#{latency}"
        )
      end

      def extract_output_text(payload)
        Array(payload['output']).flat_map do |item|
          next [] unless item['type'] == 'message'

          Array(item['content']).filter_map do |part|
            part['text'] if part['type'] == 'output_text'
          end
        end.join("\n").presence
      end

      def extract_error_message(response)
        parsed = response.parsed_response
        return parsed['error']['message'] if parsed.is_a?(Hash) && parsed.dig('error', 'message').present?

        "openai_responses_error_#{response.code}"
      end
    end
  end
end
