class Api::V1::Accounts::EmailCampaigns::VideosController < Api::V1::Accounts::EmailCampaigns::BaseController
  # POST email_campaigns/campaigns/:id/videos/resolve
  # Input:  { url } (YouTube/Vimeo link) OR { signed_id } (uploaded video blob) + optional { poster_signed_id }
  # Output: { provider, video_url, poster_url, mjml_block, needs_poster }
  IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  VIDEO_TYPES = %w[video/mp4 video/webm video/quicktime].freeze

  def resolve
    campaign = EmailCampaign.where(account: Current.account).find(params[:id])
    authorize campaign, :update?
    reject_user_poster_url!

    result =
      if params[:url].present?
        EmailCampaigns::VideoAsset.from_url(params[:url])
      elsif params[:signed_id].present?
        EmailCampaigns::VideoAsset.from_upload(video_url: upload_video_url(campaign), poster_url: upload_poster_url(campaign))
      else
        return render json: { error: 'email_campaign.video_input_required' }, status: :unprocessable_entity
      end

    render json: result
  rescue EmailCampaigns::VideoAsset::Error => e
    render json: { error: "email_campaign.#{e.message}" }, status: :unprocessable_entity
  end

  private

  # SSRF: only blobs already attached to THIS campaign (via assets_controller upload) are accepted.
  def upload_video_url(campaign)
    blob = campaign_blob_for_signed_id(campaign, params[:signed_id], 'video_blob_not_found')
    raise EmailCampaigns::VideoAsset::Error, 'video_blob_not_found' unless VIDEO_TYPES.include?(blob.content_type)

    url_for(blob)
  end

  def upload_poster_url(campaign)
    return nil if params[:poster_signed_id].blank?

    blob = campaign_blob_for_signed_id(campaign, params[:poster_signed_id], 'video_poster_blob_not_found')
    raise EmailCampaigns::VideoAsset::Error, 'video_poster_blob_not_found' unless IMAGE_TYPES.include?(blob.content_type)

    url_for(blob)
  end

  def campaign_blob_for_signed_id(campaign, signed_id, error_code)
    signed = ActiveStorage::Blob.find_signed(signed_id)
    blob = signed && campaign.builder_assets.blobs.find_by(id: signed.id)
    raise EmailCampaigns::VideoAsset::Error, error_code if blob.nil?

    blob
  rescue StandardError
    raise EmailCampaigns::VideoAsset::Error, error_code
  end

  def reject_user_poster_url!
    raise EmailCampaigns::VideoAsset::Error, 'video_poster_not_allowed' if params[:poster_url].present?
  end
end
