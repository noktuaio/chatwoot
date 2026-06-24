require 'rails_helper'

RSpec.describe 'CRM AI settings API', type: :request do
  around do |example|
    previous_crm = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    previous_ai = ENV.fetch('CRM_AI_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    ENV['CRM_AI_ENABLED'] = 'true'
    example.run
  ensure
    previous_crm.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_crm
    previous_ai.nil? ? ENV.delete('CRM_AI_ENABLED') : ENV['CRM_AI_ENABLED'] = previous_ai
  end

  it 'returns 404 when CRM AI is disabled' do
    account, admin = create_account_and_user
    pipeline, = create_crm_pipeline(account: account, user: admin)
    ENV['CRM_AI_ENABLED'] = 'false'

    get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings",
        headers: auth_headers(admin)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('crm.ai.disabled')
  end

  it 'lets administrators read and update pipeline AI settings' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)

    get "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings",
        headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'enabled')).to eq(true)

    patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/ai_settings",
          params: {
            ai_settings: {
              enabled: true,
              auto_move_enabled: true,
              stale_hours: 24
            },
            stage_criteria: {
              stage.id.to_s => 'Critério de teste'
            }
          },
          headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'auto_move_enabled')).to eq(true)
    expect(stage.reload.metadata['ai_criteria']).to eq('Critério de teste')
  end
end
