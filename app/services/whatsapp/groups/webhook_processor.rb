class Whatsapp::Groups::WebhookProcessor
  pattr_initialize [:inbox!, :params!]

  def perform
    return unless inbox.channel.try(:groups_enabled?)

    Array(value[:groups]).each { |group| apply(group.with_indifferent_access) }
  end

  private

  def apply(group)
    case field
    when 'group_lifecycle_update'
      apply_lifecycle(group)
    when 'group_participants_update'
      apply_participants(group)
    when 'group_settings_update'
      apply_settings(group)
    when 'group_status_update'
      apply_status(group)
    end
  end

  def apply_lifecycle(group)
    return log_group_error(group) if group[:errors].present?
    return create_group(group) if group[:type] == 'group_create'
    return unless group[:type] == 'group_delete'

    delete_group(group)
  end

  def create_group(group)
    conversation = find_conversation(group[:group_id])
    created = conversation.nil?
    conversation ||= create_conversation(group)
    merge_metadata(conversation, lifecycle_metadata(group))
    conversation.save!
    activity(conversation, I18n.t('conversations.activity.whatsapp_group.created')) if created
  end

  def delete_group(group)
    conversation = find_conversation(group[:group_id])
    return if conversation.blank?

    activity(conversation, I18n.t('conversations.activity.whatsapp_group.deleted'))
    conversation.resolved! unless conversation.resolved?
  end

  def apply_participants(group)
    conversation = find_conversation(group[:group_id])
    return if conversation.blank?

    case group[:type]
    when 'group_participants_add'
      Array(group[:added_participants]).each { |participant| add_participant(conversation, participant) }
    when 'group_participants_remove'
      Array(group[:removed_participants]).each { |participant| remove_participant(conversation, participant) }
    end
  end

  def apply_settings(group)
    conversation = find_conversation(group[:group_id])
    return if conversation.blank?

    subject = group.dig(:group_subject, :text) if group.dig(:group_subject, :update_successful)
    description = group.dig(:group_description, :text) if group.dig(:group_description, :update_successful)
    conversation.group_title = subject if subject.present?
    merge_metadata(conversation, { 'description' => description }.compact)
    conversation.save!
  end

  def apply_status(group)
    conversation = find_conversation(group[:group_id])
    return if conversation.blank?

    case group[:type]
    when 'group_suspend'
      merge_metadata(conversation, { 'suspended' => true })
      conversation.save!
      activity(conversation, I18n.t('conversations.activity.whatsapp_group.suspended'))
    when 'group_suspend_cleared'
      merge_metadata(conversation, { 'suspended' => false })
      conversation.save!
      activity(conversation, I18n.t('conversations.activity.whatsapp_group.suspension_cleared'))
    end
  end

  def add_participant(conversation, participant)
    contact = Whatsapp::Groups::ParticipantResolver.new(inbox: inbox, participant: participant).perform
    return if contact.blank?
    return if conversation.includes_contact?(contact)

    conversation.group_contacts.create!(contact: contact)
    activity(conversation, I18n.t('conversations.activity.whatsapp_group.participant_joined', name: contact.name))
  end

  def remove_participant(conversation, participant)
    contact = Whatsapp::Groups::ParticipantResolver.new(inbox: inbox, participant: participant).perform
    return if contact.blank?

    conversation.group_contacts.find_by(contact_id: contact.id)&.destroy!
    activity(conversation, I18n.t('conversations.activity.whatsapp_group.participant_left', name: contact.name))
  end

  def create_conversation(group)
    Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      group: true,
      group_source_id: group[:group_id].to_s,
      group_title: group[:subject].presence,
      additional_attributes: { 'whatsapp_group' => lifecycle_metadata(group) }
    )
  rescue ActiveRecord::RecordNotUnique
    find_conversation(group[:group_id])
  end

  def find_conversation(group_id)
    return if group_id.blank?

    inbox.conversations.find_by(group: true, group_source_id: group_id.to_s)
  end

  def lifecycle_metadata(group)
    {
      'invite_link' => group[:invite_link],
      'join_approval_mode' => group[:join_approval_mode],
      'request_id' => group[:request_id]
    }.compact
  end

  def merge_metadata(conversation, metadata)
    current = conversation.additional_attributes.is_a?(Hash) ? conversation.additional_attributes.deep_dup : {}
    current['whatsapp_group'] = (current['whatsapp_group'] || {}).merge(metadata)
    conversation.additional_attributes = current
  end

  def activity(conversation, content)
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: content
    )
  end

  def log_group_error(group)
    Rails.logger.warn("[WHATSAPP] Group webhook failed type=#{group[:type]} group_id=#{group[:group_id]} errors=#{group[:errors]}")
  end

  def field
    params.dig(:entry, 0, :changes, 0, :field).to_s
  end

  def value
    params.dig(:entry, 0, :changes, 0, :value) || {}
  end
end
