# frozen_string_literal: true

class Autonomia::Sso::TokenStore
  TOKEN_PURPOSE = :autonomia_identity_authorization_token
  DEFAULT_TTL = 55.minutes

  def self.write!(user_link, token)
    new(user_link).write!(token)
  end

  def self.authorization_token_for(user)
    Autonomia::UserLink
      .where(user: user)
      .where("metadata ? 'identity_authorization_token'")
      .order(updated_at: :desc, id: :desc)
      .each do |user_link|
        token = new(user_link).authorization_token
        return token if token.present?
      end

    nil
  end

  def initialize(user_link)
    @user_link = user_link
  end

  def write!(token)
    return if token.context_token.blank?

    metadata = (@user_link.metadata || {}).merge(
      'identity_authorization_token' => encryptor.encrypt_and_sign(token.context_token, purpose: TOKEN_PURPOSE),
      'identity_authorization_token_expires_at' => expires_at(token).iso8601
    )
    @user_link.update!(metadata: metadata)
  end

  def authorization_token
    return if token_expired?

    encrypted_token = @user_link.metadata&.fetch('identity_authorization_token', nil)
    return if encrypted_token.blank?

    encryptor.decrypt_and_verify(encrypted_token, purpose: TOKEN_PURPOSE)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  private

  def token_expired?
    expires_at = @user_link.metadata&.fetch('identity_authorization_token_expires_at', nil)
    return true if expires_at.blank?

    Time.zone.parse(expires_at).past?
  rescue ArgumentError
    true
  end

  def expires_at(token)
    ttl = token.expires_in.to_i.positive? ? token.expires_in.to_i.seconds : DEFAULT_TTL
    Time.current + ttl
  end

  def encryptor
    key_len = ActiveSupport::MessageEncryptor.key_len
    secret = Rails.application.key_generator.generate_key('autonomia-identity-token-store', key_len)
    ActiveSupport::MessageEncryptor.new(secret, serializer: JSON)
  end
end
