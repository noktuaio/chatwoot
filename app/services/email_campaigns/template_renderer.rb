module EmailCampaigns
  # Thin Liquid wrapper for campaign subject/body. Supports {{ contact.name }},
  # {{ contact.email }}, the pt_BR convenience aliases {{ nome }} / {{ email }},
  # the recipient's imported custom_data columns and {{ unsubscribe_url }}.
  class TemplateRenderer
    # inert_unsubscribe: render {{ unsubscribe_url }} as '#' so a test-send click can
    # never unsubscribe a real contact.
    def initialize(recipient, inert_unsubscribe: false)
      @recipient = recipient
      @inert_unsubscribe = inert_unsubscribe
    end

    def render(template)
      return '' if template.blank?

      Liquid::Template.parse(template).render(drops)
    rescue Liquid::Error
      template
    end

    private

    def drops
      @drops ||= begin
        name = @recipient.name.to_s
        email = @recipient.email.to_s
        @recipient.custom_data.to_h.merge(
          'contact' => { 'name' => name, 'email' => email },
          'nome' => name,
          'email' => email,
          'unsubscribe_url' => @inert_unsubscribe ? '#' : EmailCampaigns::Unsubscribe::Token.url(@recipient)
        )
      end
    end
  end
end
