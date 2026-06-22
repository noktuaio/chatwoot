require 'rails_helper'

RSpec.describe Autonomia::Channels::BroadcastGuard do
  describe '.blocked_conversation?' do
    let(:account) { create(:account) }
    let(:channel_api) { create(:channel_api, account: account) }
    let(:inbox) { channel_api.inbox }
    let(:contact) { create(:contact, account: account) }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

    it 'blocks WAHA status conversations' do
      contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => 'status@broadcast' })

      expect(described_class.blocked_conversation?(conversation)).to be true
    end

    it 'blocks broadcast destinations from contact inbox source ids' do
      contact_inbox.update!(source_id: 'newsletter@broadcast')

      expect(described_class.blocked_conversation?(conversation)).to be true
    end

    it 'allows normal WAHA chat ids' do
      contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => '554299999999@c.us' })

      expect(described_class.blocked_conversation?(conversation)).to be false
    end
  end
end
