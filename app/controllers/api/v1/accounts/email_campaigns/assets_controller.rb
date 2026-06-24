class Api::V1::Accounts::EmailCampaigns::AssetsController < Api::V1::Accounts::EmailCampaigns::BaseController
  MAX_IMAGE_SIZE = 10.megabytes
  MAX_VIDEO_SIZE = 25.megabytes
  MAX_PDF_SIZE = 10.megabytes
  PDF_TYPE = 'application/pdf'.freeze
  IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  VIDEO_TYPES = %w[video/mp4 video/webm video/quicktime].freeze
  ALLOWED_TYPES = (IMAGE_TYPES + VIDEO_TYPES + [PDF_TYPE]).freeze

  def create
    campaign = EmailCampaign.where(account: Current.account).find(params[:id])
    authorize campaign, :update?

    file = params[:file]
    return render_unprocessable('email_campaign.asset_file_required') if file.blank?

    content_type = detected_content_type(file)
    return render_unprocessable('email_campaign.asset_unsupported_type') unless allowed_type?(content_type)
    return render_unprocessable('email_campaign.asset_too_large') if file.size > max_size_for(content_type)

    file.tempfile.rewind
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.tempfile,
      filename: file.original_filename,
      content_type: content_type,
      identify: false
    )
    campaign.builder_assets.attach(blob)
    render json: { url: url_for(blob), signed_id: blob.signed_id, content_type: content_type }
  end

  private

  def detected_content_type(file)
    file.tempfile.rewind
    Marcel::MimeType.for(file.tempfile).to_s
  ensure
    file.tempfile.rewind if file.respond_to?(:tempfile) && file.tempfile
  end

  def allowed_type?(content_type)
    ALLOWED_TYPES.include?(content_type)
  end

  def max_size_for(content_type)
    return MAX_VIDEO_SIZE if VIDEO_TYPES.include?(content_type)
    return MAX_PDF_SIZE if content_type == PDF_TYPE

    MAX_IMAGE_SIZE
  end

  def render_unprocessable(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
