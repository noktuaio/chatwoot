module EmailCampaigns
  class EmailNormalizer
    Error = Class.new(StandardError)
    Result = Struct.new(:email, :masked, keyword_init: true)

    def self.normalize!(raw)
      email = raw.to_s.strip.downcase
      raise Error, 'blank_email' if email.blank?
      raise Error, 'invalid_email' unless email.match?(EmailCampaign::EMAIL_REGEX)

      Result.new(email: email, masked: mask(email))
    end

    def self.mask(email)
      local, _at, domain = email.partition('@')
      head = local[0]
      "#{head}#{'*' * [local.length - 1, 1].max}@#{domain}"
    end
  end
end
