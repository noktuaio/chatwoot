require 'rails_helper'

RSpec.describe WhatsappApiCampaigns::TemplateRenderer do
  it 'renders the two supported contact variables' do
    contact = Contact.new(name: 'Ana Maria')

    rendered = described_class.new(
      template: 'Olá {{contact.first_name}} de {{ contact.name }}',
      contact: contact
    ).render

    expect(rendered).to eq('Olá Ana de Ana Maria')
  end

  it 'detects unsupported variables' do
    unsupported = described_class.unsupported_variables_in('Olá {{contact.email}} {{ contact.name }}')

    expect(unsupported).to eq(['contact.email'])
  end
end
