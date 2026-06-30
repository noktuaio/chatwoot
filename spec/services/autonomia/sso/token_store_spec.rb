# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Autonomia::Sso::TokenStore do
  describe '.authorization_token_for' do
    Token = Struct.new(:context_token, :expires_in, keyword_init: true)

    it 'uses the newest valid token when the user also has registration-only links' do
      user = create(:user)
      Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'registration-user-id',
        email: user.email,
        metadata: {
          'registration_checkout' => {
            'user_subscription_id' => 'subscription-123'
          }
        }
      )
      valid_link = Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'sso-user-id',
        email: user.email,
        metadata: {
          'identity_user' => {
            'id' => 'sso-user-id',
            'email' => user.email
          }
        }
      )

      described_class.write!(valid_link, Token.new(context_token: 'valid-context-token', expires_in: 3600))

      expect(described_class.authorization_token_for(user)).to eq('valid-context-token')
    end

    it 'skips expired tokens' do
      user = create(:user)
      expired_link = Autonomia::UserLink.create!(
        user: user,
        identity_user_id: 'expired-sso-user-id',
        email: user.email
      )

      described_class.write!(expired_link, Token.new(context_token: 'expired-context-token', expires_in: -1))

      expect(described_class.authorization_token_for(user)).to be_nil
    end
  end
end
