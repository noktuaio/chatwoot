class Api::V1::Accounts::EmailCampaigns::AiController < Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :ensure_ai_enabled
  before_action :ensure_ai_credential

  ASSET_PARAMS = %i[kind url signed_id description role video_url poster_url poster_signed_id].freeze
  # Limite do MJML base alimentado no prompt de adaptação (mesmo do Generator) — validado já no
  # controller p/ rejeitar cedo, sem enfileirar.
  MAX_BASE_MJML_BYTES = 120_000

  REWRITE_SCHEMA = {
    name: 'email_campaign_rewrite',
    schema: {
      type: 'object',
      properties: { text: { type: 'string' } },
      required: ['text'],
      additionalProperties: false
    }
  }.freeze

  # Builder copilot ASSÍNCRONO: enfileira a geração (OpenAI background) e retorna 202 na hora — o
  # SubmitJob/PollJob fazem o trabalho de minutos sem segurar a thread web, persistem o resultado
  # na campanha (durável: o usuário pode sair e voltar) e avisam via ActionCable.
  def generate
    authorize EmailCampaign, :create?
    campaign = EmailCampaign.where(account: Current.account).find(params[:campaign_id])
    if params[:base_mjml].to_s.bytesize > MAX_BASE_MJML_BYTES
      return render json: { error: 'email_campaign.base_mjml_too_large' }, status: :unprocessable_entity
    end

    token = campaign.ai_begin!
    EmailCampaigns::Ai::SubmitJob.perform_later(campaign.id, token, generation_params)
    render json: { ai_status: campaign.ai_status }, status: :accepted
  end

  # Polling de fallback (o caminho feliz é o ActionCable). Estado leve da geração da campanha.
  def status
    campaign = EmailCampaign.where(account: Current.account).find(params[:id])
    render json: { ai_status: campaign.ai_status, ai_error: campaign.ai_error, ai_completed_at: campaign.ai_completed_at }
  end

  # Reescrita de trecho — rápida (modelo mini, low effort), permanece SÍNCRONA.
  def rewrite
    authorize EmailCampaign, :create?

    response = client.create(
      model: Crm::Ai::Config::MODEL_FOLLOWUP,
      instructions: EmailCampaigns::Ai::PromptBuilder.rewrite(instruction: params[:instruction].to_s),
      input: params[:text].to_s,
      schema: REWRITE_SCHEMA
    )
    render json: { text: JSON.parse(response[:text])['text'] }
  rescue Crm::Ai::ResponsesClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def generation_params
    {
      'brief' => params[:brief].to_s,
      'placeholders' => Array(params[:placeholders]),
      'assets' => permitted_assets,
      'base_mjml' => params[:base_mjml].to_s.presence
    }
  end

  def permitted_assets
    Array(params[:assets]).map do |asset|
      permitted = asset.respond_to?(:permit) ? asset.permit(*ASSET_PARAMS).to_h : asset.to_h
      permitted.with_indifferent_access
    end
  end

  def ensure_ai_enabled
    return if Crm::Ai::Config.enabled?

    render json: { error: 'ai_disabled' }, status: :unprocessable_entity
  end

  def ensure_ai_credential
    @credential = Crm::Ai::CredentialResolver.new(account: Current.account).resolve
    render json: { error: 'ai_not_configured' }, status: :unprocessable_entity if @credential.blank?
  end

  def client
    @client ||= Crm::Ai::ResponsesClient.new(credential: @credential)
  end
end
