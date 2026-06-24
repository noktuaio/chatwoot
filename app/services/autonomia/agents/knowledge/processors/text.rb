module Autonomia
  module Agents
    module Knowledge
      module Processors
        # txt e md: leitura direta dos bytes anexados. Para md aplica um strip leve de marcação
        # (cabeçalhos, ênfase, links) — o conteúdo textual é o que importa p/ embeddings.
        class Text < Base
          def extract
            text = download_bytes.to_s.dup.force_encoding('UTF-8')
            text = text.scrub('') unless text.valid_encoding?
            @source.source_type == 'md' ? strip_markdown(text) : text
          end

          private

          def strip_markdown(text)
            text
              .gsub(/^\#{1,6}\s*/, '')                       # cabeçalhos
              .gsub(/(\*\*|__|\*|_|`)/, '')                  # ênfase / inline code
              .gsub(/!?\[([^\]]*)\]\([^)]*\)/, '\1')         # links/imagens -> texto
              .gsub(/^\s{0,3}>\s?/, '')                      # blockquotes
          end
        end
      end
    end
  end
end
