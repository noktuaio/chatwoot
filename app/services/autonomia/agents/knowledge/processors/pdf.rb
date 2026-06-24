module Autonomia
  module Agents
    module Knowledge
      module Processors
        # pdf: extração de texto via gem `pdf-reader` (PDF::Reader). A gem é opcional neste fork —
        # se ausente, degrada p/ UnsupportedFormat (a fonte vira `failed` com mensagem clara) em vez
        # de quebrar o boot. Concatena o texto de cada página.
        class Pdf < Base
          def extract
            ensure_gem!
            text = +''
            with_tempfile do |path|
              reader = PDF::Reader.new(path)
              reader.pages.each { |page| text << page.text << "\n" }
            end
            text.force_encoding('UTF-8').scrub('')
          rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
            raise ExtractionError, "pdf_parse_failed: #{e.message}"
          end

          private

          def ensure_gem!
            require 'pdf-reader'
          rescue LoadError
            raise UnsupportedFormat, 'pdf_support_unavailable'
          end
        end
      end
    end
  end
end
