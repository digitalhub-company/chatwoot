module ActionCableListener::GroupContactEvents
  include Events::Types

  def conversation_contact_added(event)
    broadcast_to_inbox_members(event, CONVERSATION_CONTACT_ADDED)
  end

  def conversation_contact_removed(event)
    broadcast_to_inbox_members(event, CONVERSATION_CONTACT_REMOVED)
  end

  private

  def contact_inbox_tokens(contact_inbox)
    return [] if contact_inbox.nil?

    contact = contact_inbox.contact
    return [contact_inbox.pubsub_token] unless contact_inbox.hmac_verified?

    contact.contact_inboxes.where(hmac_verified: true).filter_map(&:pubsub_token)
  end
end
