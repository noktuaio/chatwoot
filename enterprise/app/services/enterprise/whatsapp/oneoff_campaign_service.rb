module Enterprise::Whatsapp::OneoffCampaignService
  def perform
    validate_campaign!
    deliveries = create_deliveries(extract_audience_labels)

    # marks campaign completed so that other jobs won't pick it up
    campaign.completed!
    process_deliveries(deliveries)
  end

  private

  def process_delivery(delivery)
    contact = delivery.contact
    Rails.logger.info "Processing contact: #{contact.name} (#{contact.phone_number})"

    if contact.phone_number.blank?
      Rails.logger.info "Skipping contact #{contact.name} - no phone number"
      delivery.mark_skipped!('Phone number is missing')
      return
    end

    if campaign.template_params.blank?
      Rails.logger.error "Skipping contact #{contact.name} - no template_params found for WhatsApp campaign"
      delivery.mark_skipped!('Template parameters are missing')
      return
    end

    processed_template_params = process_liquid_template_params(contact)
    if processed_template_params.nil?
      delivery.mark_skipped!('Template parameters could not be resolved')
      return
    end

    delivery.update!(message_content: rendered_message_content(contact))

    send_whatsapp_template_message(delivery: delivery, to: contact.phone_number, template_params: processed_template_params)
  end

  def create_deliveries(audience_labels)
    contacts = campaign.account.contacts.tagged_with(audience_labels, any: true)
    Rails.logger.info "Processing #{contacts.count} contacts for campaign #{campaign.id}"

    contacts.find_each.map do |contact|
      campaign.campaign_deliveries.find_or_create_by!(contact: contact) do |delivery|
        delivery.account = campaign.account
        delivery.inbox = campaign.inbox
      end
    end
  end

  def process_deliveries(deliveries)
    deliveries.each { |delivery| process_delivery(delivery) }

    Rails.logger.info "Campaign #{campaign.id} processing completed"
  end

  def rendered_message_content(contact)
    Liquid::CampaignTemplateService.new(campaign: campaign, contact: contact).call(campaign.message)
  end

  def send_whatsapp_template_message(delivery:, to:, template_params:)
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      delivery.mark_skipped!('Template name could not be resolved')
      return
    end

    source_id = channel.send_template(to, template_info(name, namespace, lang_code, processed_parameters), nil)

    update_delivery_from_provider_response(delivery, source_id)
  rescue StandardError => e
    Rails.logger.error "Failed to send WhatsApp template message to #{to}: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join('\n')}"
    delivery.mark_failed!(message: e.message)
    # continue processing remaining contacts
    nil
  end

  def template_info(name, namespace, lang_code, processed_parameters)
    {
      name: name,
      namespace: namespace,
      lang_code: lang_code,
      parameters: processed_parameters
    }
  end

  def update_delivery_from_provider_response(delivery, source_id)
    if source_id.present?
      delivery.mark_sent!(source_id)
    else
      delivery.mark_failed!(channel.last_provider_error || { message: 'WhatsApp provider did not return a message id' })
    end
  end
end
