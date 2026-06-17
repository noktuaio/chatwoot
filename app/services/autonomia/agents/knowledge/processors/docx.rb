module Autonomia
  module Agents
    module Knowledge
      module Processors
        # docx: um .docx é um zip com word/document.xml. Abre o zip (gem `rubyzip`), lê o XML do
        # documento e extrai os nós de texto `w:t` via Nokogiri, inserindo quebras por parágrafo.
        # Se `rubyzip` não estiver disponível, degrada p/ UnsupportedFormat (fonte vira `failed`).
        class Docx < Base
          DOCUMENT_PATH = 'word/document.xml'.freeze
          NS = { 'w' => 'http://schemas.openxmlformats.org/wordprocessingml/2006/main' }.freeze
          MAX_DECOMPRESSED_BYTES = 50_000_000 # teto do XML descomprimido (anti zip-bomb)

          def extract
            ensure_gem!
            # rescue de Zip::Error só DEPOIS do ensure_gem!: se a gem estiver ausente, ensure_gem!
            # levanta UnsupportedFormat e a constante `Zip` (indefinida) não chega a ser avaliada.
            begin
              xml = read_document_xml
              doc = Nokogiri::XML(xml)
              doc.xpath('//w:p', NS).map { |para| paragraph_text(para) }.reject(&:empty?).join("\n")
            rescue Zip::Error => e
              raise ExtractionError, "docx_parse_failed: #{e.message}"
            end
          end

          private

          def paragraph_text(para)
            para.xpath('.//w:t', NS).map(&:text).join.strip
          end

          def read_document_xml
            with_tempfile do |path|
              Zip::File.open(path) do |zip|
                entry = zip.find_entry(DOCUMENT_PATH)
                raise ExtractionError, 'docx_missing_document' if entry.nil?
                # Cap pelo tamanho DESCOMPRIMIDO declarado antes de ler (anti zip-bomb): um .docx de
                # poucos KB pode declarar GBs de document.xml.
                raise ExtractionError, 'docx_too_large' if entry.size > MAX_DECOMPRESSED_BYTES

                entry.get_input_stream.read(MAX_DECOMPRESSED_BYTES).to_s.force_encoding('UTF-8')
              end
            end
          end

          def ensure_gem!
            require 'zip'
          rescue LoadError
            raise UnsupportedFormat, 'docx_support_unavailable'
          end
        end
      end
    end
  end
end
