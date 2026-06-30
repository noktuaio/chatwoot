# frozen_string_literal: true

class Api::V1::Accounts::Autonomia::FinancialController < Api::V1::Accounts::BaseController
  before_action :ensure_account_administrator
  before_action :ensure_auth_session

  def subscription
    render json: financial_client.fetch!(:subscription)
  end

  def billing_preview
    render json: financial_client.fetch!(:billing_preview)
  end

  def invoices
    render json: financial_client.fetch!(:invoices)
  end

  def payments
    render json: financial_client.fetch!(:payments)
  end

  private

  def ensure_account_administrator
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  def ensure_auth_session
    token = Autonomia::Sso::TokenStore.authorization_token_for(Current.user)
    return @autonomia_financial_token = token if token.present?

    render json: { error: 'Sua sessao do Auth expirou. Saia e entre novamente para acessar o financeiro.' },
           status: :unauthorized
  end

  def financial_client
    Autonomia::Financial::Client.new(authorization_token: @autonomia_financial_token)
  end

  rescue_from Autonomia::Financial::Client::Error do |error|
    render json: { error: error.message, details: error.payload }, status: error.status
  end
end
