require 'rails_helper'

RSpec.describe Crm::Ai::DefaultStageCriteria do
  it 'returns criteria for default stage names' do
    expect(described_class.criteria_for('Novo')).to include('Primeiro contato')
    expect(described_class.criteria_for('Perdido')).to include('sem conversão')
  end

  it 'builds metadata for known stages' do
    expect(described_class.metadata_for('Proposta')).to eq(
      'ai_criteria' => described_class.criteria_for('Proposta')
    )
  end
end
