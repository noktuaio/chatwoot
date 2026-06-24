module Autonomia
  module Agents
    module Knowledge
      module Processors
        # Interface comum dos processadores: #initialize(source) + #extract -> String.
        # Oferece helpers p/ ler o arquivo anexado (ActiveStorage) da fonte e p/ sinalizar formato
        # não suportado (gem ausente) de forma uniforme (-> source vira `failed` com msg clara).
        class Base
          class UnsupportedFormat < StandardError; end
          class ExtractionError < StandardError; end

          def initialize(source)
            @source = source
          end

          # Subclasses sobrescrevem. Retorna o texto bruto extraído (String).
          def extract
            raise NotImplementedError
          end

          private

          # Verdadeiro se há um arquivo ActiveStorage anexado à fonte.
          def attached?
            @source.respond_to?(:file) && @source.file.respond_to?(:attached?) && @source.file.attached?
          end

          # Bytes do arquivo anexado. Levanta ExtractionError se não houver anexo.
          def download_bytes
            raise ExtractionError, 'missing_attachment' unless attached?

            @source.file.download
          end

          # Caminho temporário em disco do anexo (alguns parsers precisam de File/path).
          # Cede o bloco com o path e remove o tmpfile ao fim.
          def with_tempfile
            raise ExtractionError, 'missing_attachment' unless attached?

            ext = File.extname(@source.reference.to_s).presence || ".#{@source.source_type}"
            file = Tempfile.new(['autonomia_source', ext])
            file.binmode
            file.write(@source.file.download)
            file.flush
            file.rewind
            yield file.path
          ensure
            file&.close
            file&.unlink
          end
        end
      end
    end
  end
end
