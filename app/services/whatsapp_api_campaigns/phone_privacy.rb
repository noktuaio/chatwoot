module WhatsappApiCampaigns
  module PhonePrivacy
    module_function

    def mask(phone_number)
      digits = phone_number.to_s.gsub(/\D/, '')
      return '' if digits.blank?

      suffix = digits.last(4)
      "+#{digits.first(2)}*****#{suffix}"
    end

    def hash(phone_number)
      return if phone_number.blank?

      OpenSSL::Digest::SHA256.hexdigest(phone_number.to_s)
    end
  end
end
