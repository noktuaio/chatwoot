require 'rails_helper'

RSpec.describe CampaignImports::PhoneNormalizer do
  it 'normalizes Brazilian mobile phones to E.164' do
    expect(described_class.normalize!('11987654321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('5511987654321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('+5511987654321').phone_number).to eq('+5511987654321')
    expect(described_class.normalize!('(11) 98765-4321').phone_number).to eq('+5511987654321')
  end

  it 'rejects Brazilian landlines' do
    expect { described_class.normalize!('(11) 3456-4321') }.to raise_error(
      described_class::Error,
      'invalid_brazilian_mobile_number'
    )
  end
end
