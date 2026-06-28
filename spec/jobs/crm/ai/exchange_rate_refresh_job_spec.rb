require 'rails_helper'

RSpec.describe Crm::Ai::ExchangeRateRefreshJob, type: :job do
  it 'refreshes the USD to BRL cache' do
    allow(Crm::Ai::ExchangeRate).to receive(:refresh!)

    described_class.perform_now

    expect(Crm::Ai::ExchangeRate).to have_received(:refresh!)
  end
end
