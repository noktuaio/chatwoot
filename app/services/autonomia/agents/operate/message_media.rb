module Autonomia
  module Agents
    module Operate
      # Track B (Onda 2): extrai a mídia das mensagens INCOMING do turno atual (as que o cliente acabou
      # de mandar) e a converte no que o Answerer consome:
      #   - imagem/figurinha (file_type:image) -> data-url base64 inline (input_image). Lê o blob via
      #     ActiveStorage (`blob.download`), NUNCA URL pública/assinada -> anti-SSRF e sem vazar signed URL.
      #     Allowlist de content-type (IMAGE_CONTENT_TYPES) + <= MAX_IMAGE_BYTES + teto MAX_IMAGES_PER_MESSAGE.
      #   - áudio (file_type:audio) -> transcrição via Crm::Ai::TranscriptionClient (cred OpenAI da conta,
      #     NÃO loga o conteúdo), cacheada em attachment.meta['transcribed_text'] (chave compartilhada com a EE).
      #
      # Fail-safe: erro em um anexo é engolido (o turno segue com o que deu certo). NUNCA loga base64 nem
      # o texto transcrito. Stickers do WhatsApp chegam como file_type:image (webp) -> cobertos pelo path de imagem.
      class MessageMedia
        Result = Struct.new(:images, :transcripts, keyword_init: true) do
          def empty?
            images.empty? && transcripts.empty?
          end
        end

        EMPTY = Result.new(images: [], transcripts: []).freeze

        def initialize(messages:, agent:)
          @messages = Array(messages)
          @agent = agent
        end

        # -> Result (images: [data-url], transcripts: [String])
        def extract
          attachments = @messages.flat_map { |message| message.attachments.to_a }
          return EMPTY if attachments.empty?

          Result.new(images: collect_images(attachments), transcripts: collect_transcripts(attachments))
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] media_extract_failed agent=#{@agent.id} #{e.class}")
          EMPTY
        end

        private

        def collect_images(attachments)
          attachments
            .select { |attachment| attachment.file_type.to_s == 'image' }
            .first(Config::MAX_IMAGES_PER_MESSAGE) # capa ANTES de baixar: limita blob.download a <=4
            .filter_map { |attachment| image_data_url(attachment) }
        end

        # Blob -> data-url base64. Checa byte_size ANTES de baixar (evita carregar um anexo gigante na
        # memória) e DEPOIS (defesa em profundidade). content-type validado contra a allowlist do builder.
        def image_data_url(attachment)
          blob = attachment.file&.blob
          return if blob.blank?

          content_type = blob.content_type.to_s.downcase.split(';').first
          return unless Config::IMAGE_CONTENT_TYPES.include?(content_type)
          return if blob.byte_size > Config::MAX_IMAGE_BYTES

          data = blob.download
          return if data.blank? || data.bytesize > Config::MAX_IMAGE_BYTES

          "data:#{content_type};base64,#{Base64.strict_encode64(data)}"
        rescue StandardError
          nil # anexo ilegível -> descarta a imagem, mantém o turno. NUNCA loga o conteúdo.
        end

        def collect_transcripts(attachments)
          # Capa ANTES de transcrever: limita a custo/latência da API a no máximo MAX_AUDIO_PER_MESSAGE.
          audios = attachments.select { |attachment| attachment.file_type.to_s == 'audio' }
                              .first(Config::MAX_AUDIO_PER_MESSAGE)
          return [] if audios.empty?

          credential = Crm::Ai::CredentialResolver.new(account: @agent.account).resolve
          return [] if credential.blank?

          audios.filter_map { |attachment| transcript_for(attachment, credential) }
        end

        # Transcreve (ou reusa o cache compartilhado). NUNCA loga o texto. Falha de transcrição -> nil (o
        # prompt v2 manda pedir o texto/resumo quando não há transcrição).
        def transcript_for(attachment, credential)
          cached = attachment.meta.to_h['transcribed_text'].to_s
          return cached if cached.present?

          text = Crm::Ai::TranscriptionClient.new(credential: credential).transcribe(attachment).to_s.strip
          return if text.blank?

          cache_transcript(attachment, text) # best-effort: a transcrição alimenta ESTE turno mesmo se o cache falhar
          text
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] transcription_failed attachment=#{attachment.id} #{e.class}")
          nil
        end

        # Cache compartilhado (attachment.meta['transcribed_text']). Recarrega antes do merge p/ reduzir
        # sobrescrita de chaves concorrentes; NUNCA derruba o turno se a escrita falhar (rescue -> nil).
        def cache_transcript(attachment, text)
          attachment.reload
          attachment.update!(meta: attachment.meta.to_h.merge('transcribed_text' => text))
        rescue StandardError
          nil
        end
      end
    end
  end
end
