module GoogleConcern
  extend ActiveSupport::Concern

  GOOGLE_CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar'.freeze

  def google_client
    creds = ::EmailOauth::CredentialResolver.new(oauth_account, 'google').credentials

    ::OAuth2::Client.new(creds[:client_id], creds[:client_secret], {
                           site: 'https://oauth2.googleapis.com',
                           authorize_url: 'https://accounts.google.com/o/oauth2/auth',
                           token_url: 'https://accounts.google.com/o/oauth2/token'
                         })
  end

  private

  def scope
    base_scope = 'email profile https://mail.google.com/'
    return base_scope unless request_calendar_scope?

    "#{base_scope} #{GOOGLE_CALENDAR_SCOPE}"
  end

  # Calendar = a capability of the agent's mailbox: when the meetings feature is
  # on, every Google mailbox connect also requests calendar access (one consent),
  # so scheduling works without a second OAuth round.
  def request_calendar_scope?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('CRM_CALENDAR_MEETINGS_ENABLED', false)) || calendar_oauth_intent?
  end

  def calendar_oauth_intent?
    state_params = (session[:oauth_state_params] || {}).with_indifferent_access

    params[:calendar_intent].present? ||
      params[:intent].to_s == 'calendar' ||
      params[:oauth_intent].to_s == 'calendar' ||
      state_params[:calendar_intent].present? ||
      state_params[:intent].to_s == 'calendar' ||
      state_params[:oauth_intent].to_s == 'calendar'
  end
end
