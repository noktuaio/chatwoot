module Autonomia
  module Agents
    module Knowledge
      module Processors
        # link: baixa UMA página (a url dada — sem crawl recursivo na v1) via SafeFetch/SsrfFilter,
        # que resolve uma vez, REJEITA faixas privadas/loopback/link-local/metadata e CONECTA no IP
        # validado (sem TOCTOU/DNS-rebinding), re-valida cada redirect por hop e faz streaming com
        # teto de bytes (sem bufferizar a página inteira). Extrai o texto visível com Nokogiri.
        class Link < Base
          MAX_BYTES = 5_000_000 # teto defensivo p/ páginas gigantes (aplicado durante o streaming)
          # SafeFetch valida content-type; HTML/texto são os aceitáveis para ingestão de página.
          ALLOWED_TYPE_PREFIXES = %w[text/ application/xhtml].freeze
          ALLOWED_TYPES = %w[application/xhtml+xml application/xml application/json].freeze
          NON_CONTENT = %w[script style noscript template svg iframe nav footer header].freeze

          def extract
            # Pré-check barato (esquema/host óbvio); a proteção AUTORITATIVA anti-SSRF é o SafeFetch.
            UrlGuard.new(target_url).validate!
            visible_text(fetch_html(target_url))
          rescue UrlGuard::BlockedUrl, SafeFetch::UnsafeUrlError, SafeFetch::InvalidUrlError => e
            raise ExtractionError, "blocked_url: #{e.message}"
          rescue SafeFetch::FileTooLargeError
            raise ExtractionError, 'too_large'
          rescue SafeFetch::HttpError => e
            raise ExtractionError, "http_error: #{e.message}"
          rescue SafeFetch::UnsupportedContentTypeError => e
            raise ExtractionError, "unsupported_type: #{e.message}"
          rescue SafeFetch::Error => e
            raise ExtractionError, "fetch_failed: #{e.class.name.demodulize.underscore}"
          end

          private

          # Busca SSRF-safe e com cap de memória. SafeFetch faz o streaming p/ um tempfile e levanta
          # FileTooLargeError ao passar do MAX_BYTES (nunca carrega a página inteira na memória).
          def fetch_html(url)
            SafeFetch.fetch(
              url,
              max_bytes: MAX_BYTES,
              headers: { 'User-Agent' => 'AutonomiaAgentBot/1.0' },
              allowed_content_type_prefixes: ALLOWED_TYPE_PREFIXES,
              allowed_content_types: ALLOWED_TYPES
            ) { |result| result.tempfile.read }
          end

          def target_url
            @source.external_link.presence || @source.reference
          end

          def visible_text(html)
            doc = Nokogiri::HTML(html)
            doc.search(*NON_CONTENT).remove
            doc.text.gsub(/[ \t]+/, ' ').gsub(/\n{2,}/, "\n\n").strip
          end
        end
      end
    end
  end
end
