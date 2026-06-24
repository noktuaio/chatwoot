require 'rails_helper'

RSpec.describe Crm::Ai::Evaluator do
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

  it 'skips when confidence is below suggestion threshold' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    target_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
    target_stage.update!(metadata: { 'ai_criteria' => 'Proposta enviada' })
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead',
      currency: 'BRL'
    )

    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test', api_base: 'https://api.openai.com' })
    )
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(
      instance_double(
        Crm::Ai::StageClassifier,
        perform: {
          suggested_stage_id: target_stage.id,
          confidence: 0.5,
          reasoning: 'Baixa confiança',
          model_used: 'gpt-5.4-mini'
        }
      )
    )

    result = described_class.new(card: card).perform
    expect(result.status).to eq(:below_threshold)
    expect(account.crm_ai_stage_suggestions.where(card: card).count).to eq(0)
  end

  it 'creates a pending suggestion when confidence is between thresholds' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    target_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
    target_stage.update!(metadata: { 'ai_criteria' => 'Proposta enviada' })
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead',
      currency: 'BRL'
    )

    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test', api_base: 'https://api.openai.com' })
    )
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(
      instance_double(
        Crm::Ai::StageClassifier,
        perform: {
          suggested_stage_id: target_stage.id,
          confidence: 0.65,
          reasoning: 'Cliente pediu orçamento',
          model_used: 'gpt-5.4-mini'
        }
      )
    )

    result = described_class.new(card: card).perform
    expect(result.status).to eq(:suggested)
    expect(result.suggestion).to be_pending
    expect(result.suggestion.to_stage_id).to eq(target_stage.id)
  end
end
