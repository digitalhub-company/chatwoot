module Whatsapp::Providers::WhatsappCloudGroupDelivery
  private

  # 1:1 sends stay on the existing Messages API path. Group sends use the configured Graph
  # version because recipient_type=group is part of the current Groups API.
  # https://developers.facebook.com/documentation/business-messaging/whatsapp/groups/groups-messaging
  def message_api_path(message)
    return phone_id_path unless group_message?(message)

    version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
    "#{api_base_path}/#{version}/#{whatsapp_channel.provider_config['phone_number_id']}"
  end

  def group_message?(message)
    message.conversation&.group?
  end

  def message_recipient_params(phone_number, message)
    return { recipient_type: 'group', to: message.conversation.group_source_id } if group_message?(message)

    recipient_params(phone_number)
  end

  def template_recipient_params(phone_number, message)
    return message_recipient_params(phone_number, message) if group_message?(message)

    { recipient_type: 'individual', **recipient_params(phone_number) }
  end

  def unsupported_group_message?(message)
    group_message?(message) && message.content_type == 'input_select'
  end

  def unsupported_group_template?(message, template_info)
    group_message?(message) && template_info[:category].to_s.casecmp('authentication').zero?
  end

  def reject_unsupported_group_message(message)
    message.update!(status: :failed, external_error: I18n.t('errors.whatsapp.group_interactive_unsupported'))
    nil
  end

  def reject_unsupported_group_template(message)
    message.update!(status: :failed, external_error: I18n.t('errors.whatsapp.group_authentication_template_unsupported'))
    nil
  end

  def send_text_message(phone_number, message)
    response = HTTParty.post(
      "#{message_api_path(message)}/messages",
      headers: api_headers,
      body: {
        messaging_product: 'whatsapp',
        context: whatsapp_reply_context(message),
        **message_recipient_params(phone_number, message),
        text: { body: message.outgoing_content },
        type: 'text'
      }.to_json
    )

    process_response(response, message)
  end
end
