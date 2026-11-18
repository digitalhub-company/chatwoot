class Whatsapp::Groups::ParticipantResolver
  include Whatsapp::IncomingMessageServiceHelpers
  include Whatsapp::IncomingMessageIdentifierHelper

  pattr_initialize [:inbox!, :participant!]

  def perform
    source_ids = Whatsapp::IdentitySourceIdOrderer.new(
      inbox: inbox,
      phone_source_id: whatsapp_phone_source_id(participant[:wa_id]),
      source_ids: [
        whatsapp_source_id(participant[:parent_user_id]),
        whatsapp_source_id(participant[:user_id])
      ]
    ).perform
    return if source_ids.blank?

    contact_inbox = find_or_create_contact_inbox(
      source_ids: source_ids,
      contact_attributes: contact_attributes_for_identifier(display_name(source_ids), participant[:wa_id])
    )
    sync_identifiers(contact_inbox, source_ids)
    contact_inbox.contact
  end

  private

  def display_name(source_ids)
    participant[:username].presence || participant[:wa_id].presence || source_ids.first
  end

  def sync_identifiers(contact_inbox, source_ids)
    Whatsapp::IdentifierSyncService.new(contact_inbox: contact_inbox, contact: contact_inbox.contact).perform(
      source_ids: source_ids,
      username: participant[:username],
      phone_number: whatsapp_phone_number(participant[:wa_id]).present? ? "+#{whatsapp_phone_number(participant[:wa_id])}" : nil
    )
  end
end
