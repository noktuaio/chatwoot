# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Account::MarketingAttributionService do
  let(:account) { create(:account) }
  let(:request) { instance_double(ActionDispatch::Request, referer: nil) }
  let(:cookies) { {} }

  describe '#perform' do
    before do
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
    end

    it 'stores first and last touch attribution from cookies' do
      cookies[described_class::FIRST_TOUCH_COOKIE] = encoded_cookie(
        'utm_source' => 'reddit',
        'utm_medium' => 'paid_social',
        'source' => 'reddit',
        'source_type' => 'paid_social',
        'referrer' => 'https://reddit.com',
        'referrer_path' => '/r/selfhosted/comments/123/chatwoot',
        'landing_page' => 'https://www.chatwoot.com/pricing?utm_source=reddit&utm_medium=paid_social',
        'captured_at' => '2026-06-17T10:00:00.000Z'
      )
      cookies[described_class::LAST_TOUCH_COOKIE] = encoded_cookie(
        'utm_source' => 'github',
        'utm_medium' => 'referral',
        'source' => 'github',
        'source_type' => 'referral',
        'landing_page' => 'https://www.chatwoot.com?utm_source=github&utm_medium=referral',
        'captured_at' => '2026-06-17T11:00:00.000Z'
      )

      described_class.new(account: account, cookies: cookies, request: request).perform

      attribution = account.reload.internal_attributes['marketing_attribution']
      expect(attribution['captured_from']).to eq('cookie')
      expect(attribution['first_touch']['source']).to eq('reddit')
      expect(attribution['first_touch']['referrer_path']).to eq('/r/selfhosted/comments/123/chatwoot')
      expect(attribution['last_touch']['source']).to eq('github')
    end

    it 'preserves an existing first touch and updates last touch' do
      account.update!(
        internal_attributes: {
          'marketing_attribution' => {
            'first_touch' => { 'source' => 'google', 'source_type' => 'paid_search' }
          }
        }
      )
      cookies[described_class::LAST_TOUCH_COOKIE] = encoded_cookie(
        'utm_source' => 'linkedin',
        'utm_medium' => 'paid_social',
        'source' => 'linkedin',
        'source_type' => 'paid_social'
      )

      described_class.new(account: account, cookies: cookies, request: request).perform

      attribution = account.reload.internal_attributes['marketing_attribution']
      expect(attribution['first_touch']['source']).to eq('google')
      expect(attribution['last_touch']['source']).to eq('linkedin')
    end

    it 'falls back to the request referer when cookies are unavailable' do
      request = instance_double(
        ActionDispatch::Request,
        referer: 'https://app.chatwoot.com/app/auth/signup?utm_source=google&utm_medium=cpc&gclid=abc&private_param=ignored'
      )

      described_class.new(account: account, cookies: cookies, request: request).perform

      attribution = account.reload.internal_attributes['marketing_attribution']
      expect(attribution['captured_from']).to eq('request_referer')
      expect(attribution['last_touch']).to include(
        'utm_source' => 'google',
        'utm_medium' => 'cpc',
        'gclid' => 'abc',
        'source' => 'google',
        'source_type' => 'paid_search'
      )
      expect(attribution['last_touch']['landing_page']).to include('utm_source=google')
      expect(attribution['last_touch']['landing_page']).not_to include('private_param')
    end

    it 'does not store attribution outside Chatwoot Cloud' do
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false)
      cookies[described_class::LAST_TOUCH_COOKIE] = encoded_cookie('utm_source' => 'reddit')

      described_class.new(account: account, cookies: cookies, request: request).perform

      expect(account.reload.internal_attributes).not_to include('marketing_attribution')
    end
  end

  def encoded_cookie(payload)
    CGI.escape(payload.to_json)
  end
end
