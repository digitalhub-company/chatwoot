# https://docs.360dialog.com/whatsapp-api/whatsapp-api/media
# https://developers.facebook.com/docs/whatsapp/api/media/

class Whatsapp::IncomingMessageWhatsappCloudService < Whatsapp::IncomingMessageBaseService
  GROUP_METADATA_FIELDS = %w[
    group_lifecycle_update
    group_participants_update
    group_settings_update
    group_status_update
  ].freeze

  def perform
    processed_params
    return if group_echo?
    return Whatsapp::Groups::WebhookProcessor.new(inbox: inbox, params: params).perform if group_metadata_field?
    return process_group_messages if group_message?

    super
  end

  private

  def group_metadata_field?
    GROUP_METADATA_FIELDS.include?(params.dig(:entry, 0, :changes, 0, :field).to_s)
  end

  def group_message?
    !outgoing_echo && messages_data.to_a.first&.dig(:group_id).present?
  end

  def group_echo?
    outgoing_echo && messages_data.to_a.first&.dig(:group_id).present?
  end

  # Group messages share the messages webhook, with group_id set and from identifying the
  # participant. When groups are disabled they must not fall through into a 1:1 thread.
  # https://developers.facebook.com/documentation/business-messaging/whatsapp/groups/groups-messaging
  def process_group_messages
    return unless inbox.channel.try(:groups_enabled?)
    return if unprocessable_message_type?(message_type)
    return if find_message_by_source_id(messages_data.first[:id])
    return unless lock_message_source_id!

    set_contact
    return unless @contact
    return if @contact.blocked?

    ActiveRecord::Base.transaction do
      set_group_conversation
      ensure_group_membership!
      create_messages
    end
  end

  def set_group_conversation
    group_id = messages_data.first[:group_id].to_s
    @conversation = inbox.conversations.find_by(group: true, group_source_id: group_id)
    if @conversation
      assign_primary_contact_if_missing
      return
    end

    @conversation = ::Conversation.create!(conversation_params.merge(group: true, group_source_id: group_id))
  rescue ActiveRecord::RecordNotUnique
    @conversation = inbox.conversations.find_by!(group: true, group_source_id: group_id)
    assign_primary_contact_if_missing
  end

  def assign_primary_contact_if_missing
    return if @conversation.contact_id.present?

    @conversation.update!(contact: @contact, contact_inbox: @contact_inbox)
  end

  def ensure_group_membership!
    return if @conversation.contact_id == @contact.id
    return if @conversation.group_contacts.exists?(contact_id: @contact.id)

    @conversation.group_contacts.create!(contact: @contact)
  end

  def processed_params
    @processed_params ||= params[:entry].try(:first).try(:[], 'changes').try(:first).try(:[], 'value')
  end

  def download_attachment_file(attachment_payload)
    url_response = HTTParty.get(
      inbox.channel.media_url(attachment_payload[:id]),
      headers: inbox.channel.api_headers
    )

    # This url response will be failure if the access token has expired.
    inbox.channel.authorization_error! if url_response.unauthorized?

    return unless url_response.success?

    downloaded_file = Down.download(url_response.parsed_response['url'], headers: inbox.channel.api_headers)
    # WhatsApp Cloud sends the original filename in the payload; preserve it so accented
    # names keep their correct extension instead of relying on the mangled remote metadata.
    filename = attachment_payload[:filename]
    downloaded_file.define_singleton_method(:original_filename) { filename } if filename.present?
    downloaded_file
  end
end
