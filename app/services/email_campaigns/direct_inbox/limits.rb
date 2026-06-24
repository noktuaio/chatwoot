module EmailCampaigns
  module DirectInbox
    # Limites e freios do envio DIRETO pela caixa (webmail). Números conservadores,
    # bem abaixo do teto real de cada provedor — a ideia é parecer/ser envio humano,
    # de baixo volume, para lista de relacionamento. Ver pesquisa de limites.
    module Limits
      # Domínios de webmail gratuito (mesma lista da config da caixa).
      WEBMAIL_DOMAINS = %w[
        gmail.com googlemail.com hotmail.com hotmail.com.br outlook.com outlook.com.br
        live.com msn.com yahoo.com yahoo.com.br ymail.com icloud.com me.com mac.com
        aol.com gmx.com proton.me protonmail.com bol.com.br uol.com.br terra.com.br
      ].freeze

      DEFAULT_DAILY_CAP = 100
      # Tetos por provedor (mais conservadores onde o limite real é menor).
      DAILY_CAPS = {
        'outlook.com' => 60, 'outlook.com.br' => 60, 'hotmail.com' => 60, 'hotmail.com.br' => 60,
        'live.com' => 60, 'msn.com' => 60, 'yahoo.com' => 60, 'yahoo.com.br' => 60,
        'uol.com.br' => 40, 'bol.com.br' => 40, 'terra.com.br' => 40
      }.freeze

      MIN_INTERVAL_SECONDS = 60
      MAX_INTERVAL_SECONDS = 120
      BUSINESS_HOUR_START = 9   # inclusivo
      BUSINESS_HOUR_END = 18    # exclusivo (último envio até 17:59)
      AUTOPAUSE_CONSECUTIVE_FAILURES = 3
      AUTOPAUSE_FAILURE_RATE = 0.05

      module_function

      def webmail?(email)
        WEBMAIL_DOMAINS.include?(domain_of(email))
      end

      def daily_cap(email)
        DAILY_CAPS.fetch(domain_of(email), DEFAULT_DAILY_CAP)
      end

      def domain_of(email)
        email.to_s.split('@').last.to_s.downcase
      end
    end
  end
end
