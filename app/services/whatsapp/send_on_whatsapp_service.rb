class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    return send_group_reply if message.conversation.group?

    if template_params.present?
      tag_contact_info_template_request
      return send_template_message
    end
    return send_contact_info_request if contact_info_request?

    return send_session_message if message.conversation.can_reply?

    message.update!(status: :failed, external_error: I18n.t('errors.whatsapp.message_outside_messaging_window'))
  rescue CustomExceptions::WhatsappContactInfoRequestError => e
    message.update!(status: :failed, external_error: e.message)
  end

  def send_group_reply
    unless channel.provider == 'whatsapp_cloud' && channel.groups_enabled?
      message.update!(status: :failed, external_error: I18n.t('errors.whatsapp.groups_disabled'))
      return
    end

    return send_template_message if template_params.present?
    return send_session_message if message.conversation.can_reply?

    message.update!(status: :failed, external_error: I18n.t('errors.whatsapp.message_outside_messaging_window'))
  end

  def send_contact_info_request
    Whatsapp::ContactInfoRequestEligibilityService.new(
      conversation: message.conversation, message: message, delivery_mode: :interactive
    ).ensure_available!
    message_id = channel.send_contact_info_request(message.conversation.contact_inbox.source_id, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def send_template_message
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end

    message_id = channel.send_template(recipient_source_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: processed_parameters
                                       }, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def send_session_message
    message_id = channel.send_message(recipient_source_id, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def recipient_source_id
    return message.conversation.group_source_id if message.conversation.group?

    message.conversation.contact_inbox.source_id
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end

  def contact_info_request?
    message.content_attributes.dig('whatsapp_contact_info', 'type') == 'request'
  end

  def tag_contact_info_template_request
    eligibility = Whatsapp::ContactInfoRequestEligibilityService.new(
      conversation: message.conversation, message: message, delivery_mode: :template, template_params: template_params
    )
    return unless eligibility.request_contact_info_template?(template_params)

    message.conversation.contact_inbox.with_lock do
      eligibility.ensure_available!
      content_attributes = message.content_attributes.deep_dup
      content_attributes['whatsapp_contact_info'] = { 'type' => 'request', 'state' => 'pending', 'delivery_mode' => 'template' }
      message.update!(content_attributes: content_attributes)
    end
  end
end
