module Crm
  module Ai
    # Transcribes an audio attachment to text using the CRM hook's OpenAI
    # credential (independent of Captain). Mirrors the EE
    # Messages::AudioTranscriptionService mechanics (temp file, 25MB limit,
    # temperature 0.0) and writes to the shared cache key
    # `attachment.meta['transcribed_text']`.
    class TranscriptionClient
      def initialize(credential:)
        @credential = credential
      end

      def transcribe(attachment)
        blob = attachment.file&.blob
        return if blob.blank?
        return if blob.byte_size > Config::TRANSCRIPTION_BYTE_LIMIT

        temp_file_path = download_to_temp(blob)
        File.open(temp_file_path, 'rb') do |file|
          response = client.audio.transcribe(
            parameters: {
              model: Config::TRANSCRIBE_MODEL,
              file: file,
              temperature: 0.0,
              language: 'pt'
            }
          )
          response['text']
        end
      ensure
        FileUtils.rm_f(temp_file_path) if temp_file_path.present?
      end

      private

      def client
        @client ||= OpenAI::Client.new(
          access_token: @credential[:api_key],
          uri_base: @credential[:api_base]
        )
      end

      def download_to_temp(blob)
        temp_dir = Rails.root.join('tmp/uploads/crm-ai-transcriptions')
        FileUtils.mkdir_p(temp_dir)
        temp_file_name = "#{blob.key}-#{blob.filename}"
        if blob.filename.extension_without_delimiter.blank?
          extension = extension_from_content_type(blob.content_type)
          temp_file_name = "#{temp_file_name}.#{extension}" if extension.present?
        end
        temp_file_path = File.join(temp_dir, temp_file_name)
        File.open(temp_file_path, 'wb') do |file|
          blob.open { |blob_file| IO.copy_stream(blob_file, file) }
        end
        temp_file_path
      end

      def extension_from_content_type(content_type)
        subtype = content_type.to_s.downcase.split(';').first.to_s.split('/').last.to_s
        return if subtype.blank?

        { 'x-m4a' => 'm4a', 'x-wav' => 'wav', 'x-mp3' => 'mp3' }.fetch(subtype, subtype)
      end
    end
  end
end
