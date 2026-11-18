# == Schema Information
#
# Table name: group_contacts
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  contact_id      :bigint           not null
#  conversation_id :bigint           not null
#
# Indexes
#
#  index_group_contacts_on_account_id                     (account_id)
#  index_group_contacts_on_contact_id                     (contact_id)
#  index_group_contacts_on_conversation_and_contact       (conversation_id,contact_id) UNIQUE
#  index_group_contacts_on_conversation_id                (conversation_id)
#
class GroupContact < ApplicationRecord
  attr_accessor :promoted_to_primary

  validates :account_id, presence: true
  validates :conversation_id, presence: true
  validates :contact_id, presence: true
  validates :contact_id, uniqueness: { scope: :conversation_id }
  validate :ensure_conversation_is_group
  validate :ensure_contact_belongs_to_account
  validate :ensure_not_primary_contact

  belongs_to :account
  belongs_to :conversation
  belongs_to :contact

  before_validation :ensure_account_id
  after_create :promote_to_primary_if_first_contact
  after_create_commit :dispatch_contact_added_event, unless: :promoted_to_primary
  after_destroy_commit :dispatch_contact_removed_event, unless: :promoted_to_primary

  private

  def ensure_account_id
    self.account_id ||= conversation&.account_id
  end

  def ensure_conversation_is_group
    return if conversation.blank? || conversation.group?

    errors.add(:conversation, 'must be a group conversation')
  end

  def ensure_contact_belongs_to_account
    return if contact.blank? || conversation.blank?
    return if contact.account_id == conversation.account_id

    errors.add(:contact, 'must belong to the same account')
  end

  def ensure_not_primary_contact
    return if contact.blank? || conversation.blank?
    return unless conversation.contact_id == contact.id

    errors.add(:contact, 'is already the primary contact')
  end

  def promote_to_primary_if_first_contact
    return unless conversation.group? && conversation.contact_id.nil?

    contact_inbox = contact.contact_inboxes.find_or_create_by!(inbox: conversation.inbox) do |record|
      record.source_id = contact.phone_number.presence || contact.email.presence || SecureRandom.uuid
    end
    conversation.update!(contact: contact, contact_inbox: contact_inbox)
    self.promoted_to_primary = true
    destroy!
  end

  def dispatch_contact_added_event
    Rails.configuration.dispatcher.dispatch(
      CONVERSATION_CONTACT_ADDED,
      Time.zone.now,
      conversation: conversation,
      contact: contact
    )
  end

  def dispatch_contact_removed_event
    Rails.configuration.dispatcher.dispatch(
      CONVERSATION_CONTACT_REMOVED,
      Time.zone.now,
      conversation: conversation,
      contact: contact
    )
  end
end
