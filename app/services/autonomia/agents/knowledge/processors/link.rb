module Autonomia
  module Agents
    module Knowledge
      module Processors
        # link: baixa UMA página (a url dada — sem crawl recursivo na v1), passando obrigatoriamente
        # pelo UrlGuard (anti-SSRF) antes do GET. Extrai o texto visível com Nokogiri (remove
        # script/style/nav/footer) e normaliza espaços.
        class Link < Base
          MAX_BYTES = 5_000_000 # teto defensivo p/ páginas gigantes
          MAX_REDIRECTS = 3
          NON_CONTENT = %w[script style noscript template svg iframe nav footer header].freeze

          def extract
            response = fetch_with_guarded_redirects(target_url)
            raise ExtractionError, "http_#{response.code}" unless response.success?

            html = response.body.to_s.byteslice(0, MAX_BYTES).to_s
            visible_text(html)
          rescue UrlGuard::BlockedUrl => e
            raise ExtractionError, "blocked_url: #{e.message}"
          rescue HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET => e
            raise ExtractionError, "fetch_failed: #{e.class.name.demodulize.underscore}"
          end

          private

          # SSRF-safe: desliga o follow automático do HTTParty (que seguia redirects sem revalidar) e
          # segue cada Location manualmente SÓ depois de revalidar pelo UrlGuard (anti redirect->IP
          # interno / metadados de nuvem). Limite de saltos preservado.
          def fetch_with_guarded_redirects(url)
            current = url
            (MAX_REDIRECTS + 1).times do
              safe = UrlGuard.new(current).validate!
              response = HTTParty.get(safe, timeout: 20, follow_redirects: false,
                                            headers: { 'User-Agent' => 'AutonomiaAgentBot/1.0' })
              return response unless response.is_a?(HTTParty::Response) && redirect?(response)

              location = response.headers['location'].to_s
              raise ExtractionError, 'redirect_without_location' if location.blank?

              current = absolute_location(current, location)
            end
            raise ExtractionError, 'too_many_redirects'
          end

          def redirect?(response)
            (300..399).cover?(response.code.to_i) && response.headers['location'].present?
          end

          def absolute_location(base, location)
            URI.join(base, location).to_s
          rescue URI::Error
            raise ExtractionError, 'invalid_redirect'
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
