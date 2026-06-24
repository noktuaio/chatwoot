module WhatsappApiCampaignHelpers
  def create_whatsapp_api_inbox(account:, name: 'WAHA API', enabled: true)
    channel = account.api_channels.create!(webhook_url: 'https://waha.invalid/chatwoot')
    inbox = account.inboxes.create!(name: name, channel: channel)
    channel.enable_whatsapp_api_campaigns! if enabled
    inbox.reload
  end

  def create_labelled_contact(account:, label:, name:, phone_number:)
    contact = account.contacts.create!(name: name, phone_number: phone_number)
    contact.add_labels(label.title)
    contact
  end

  def create_whatsapp_api_campaign(account:, user:, inbox:, label:, message_body: 'Olá {{contact.first_name}}')
    account.whatsapp_api_campaigns.create!(
      created_by: user,
      inbox: inbox,
      title: 'Campanha WAHA',
      status: :scheduled,
      audience: [{ type: 'Label', id: label.id }],
      message_body: message_body,
      template_snapshot: {
        body: message_body,
        variables: WhatsappApiCampaigns::TemplateRenderer.variables_in(message_body)
      },
      scheduled_at: 1.minute.ago
    )
  end

  def create_account_user_inbox_and_label
    account, user = create_account_and_user
    inbox = create_whatsapp_api_inbox(account: account)
    label = account.labels.create!(title: "clientes_#{SecureRandom.hex(3)}")
    [account, user, inbox, label]
  end
end

RSpec.configure do |config|
  config.include WhatsappApiCampaignHelpers
end
