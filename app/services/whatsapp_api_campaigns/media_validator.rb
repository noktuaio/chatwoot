module WhatsappApiCampaigns
  class MediaValidator
    ACCEPTED_PREFIXES = %w[image/ video/ audio/].freeze
    ACCEPTED_DOCUMENT_TYPES = Attachment::ACCEPTABLE_FILE_TYPES.freeze

    def initialize(file)
      @file = file
    end

    def validate!
      return if @file.blank?

      raise ArgumentError, 'media_file_too_large' if @file.size.to_i > Config.max_media_size_bytes
      raise ArgumentError, 'media_file_type_not_supported' unless accepted_content_type?
    end

    private

    def accepted_content_type?
      content_type = @file.content_type.to_s
      ACCEPTED_PREFIXES.any? { |prefix| content_type.start_with?(prefix) } ||
        ACCEPTED_DOCUMENT_TYPES.include?(content_type)
    end
  end
end
