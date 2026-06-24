require 'rails_helper'

RSpec.describe CampaignImports::HeaderMapper do
  it 'maps accepted Portuguese and English aliases' do
    result = described_class.new(['Nome Completo', 'Whatsapp']).perform

    expect(result.errors).to be_empty
    expect(result.mapping).to eq(name: 0, phone_number: 1)
  end

  it 'reports missing logical columns' do
    result = described_class.new(['email']).perform

    expect(result.errors).to include('missing_name_header', 'missing_phone_number_header')
  end
end
