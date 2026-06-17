class Api::V1::Accounts::EmailCampaigns::SenderIdentitiesController < Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :fetch_identity, only: [:show, :verify, :destroy, :dns_check]

  def index
    authorize EmailSenderIdentity
    @sender_identities = identity_scope.order(created_at: :desc)
  end

  def show; end

  def create
    @sender_identity = identity_scope.new(sender_identity_params)
    authorize @sender_identity
    @sender_identity.save!
    EmailCampaigns::Ses::IdentityProvisioner.new(@sender_identity).perform
    render :show, status: :created
  rescue EmailCampaigns::Ses::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def verify
    EmailCampaigns::DomainVerificationPollJob.perform_later(@sender_identity.id)
    render :show
  end

  # Live, per-record DNS diagnostic: resolves each expected record and reports which are
  # ok / missing / mismatch, so the user knows exactly what to fix. Also nudges SES to
  # re-check (the green-check flip remains SES's call).
  def dns_check
    records = EmailCampaigns::Dns::RecordChecker.new(@sender_identity).perform
    EmailCampaigns::DomainVerificationPollJob.perform_later(@sender_identity.id)
    render json: { records: records, status: @sender_identity.status }
  end

  def destroy
    @sender_identity.destroy!
    head :no_content
  rescue ActiveRecord::InvalidForeignKey
    render json: { error: 'sender_identity_in_use' }, status: :unprocessable_entity
  end

  private

  def identity_scope
    EmailSenderIdentity.where(account: Current.account)
  end

  def fetch_identity
    @sender_identity = identity_scope.find(params[:id])
    authorize @sender_identity
  end

  def sender_identity_params
    params.require(:sender_identity).permit(:domain, :from_email, :reply_to_inbox_id)
  end
end
