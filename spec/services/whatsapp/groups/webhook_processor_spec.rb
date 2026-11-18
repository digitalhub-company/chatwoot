require 'rails_helper'

describe Whatsapp::Groups::WebhookProcessor do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:group_id) { 'Y2FwaV9ncm91cDoxNzA1NTU1MDEzOToxMjAzNjM0MDQ2OTQyMzM4MjAZD' }

  before do
    channel.provider_config = channel.provider_config.merge('groups_enabled' => true)
    channel.save!(validate: false)
  end

  def payload(field, group)
    {
      object: 'whatsapp_business_account',
      entry: [{
        changes: [{
          field: field,
          value: {
            messaging_product: 'whatsapp',
            metadata: {
              display_phone_number: '15550001111',
              phone_number_id: channel.provider_config['phone_number_id']
            },
            groups: [group]
          }
        }]
      }]
    }.with_indifferent_access
  end

  it 'creates a group conversation from the group_create webhook and stores the invite link' do
    described_class.new(
      inbox: channel.inbox,
      params: payload('group_lifecycle_update', {
                        timestamp: '1755548877',
                        group_id: group_id,
                        type: 'group_create',
                        request_id: 'req-1',
                        subject: 'Support',
                        invite_link: 'https://chat.whatsapp.com/LINKID',
                        join_approval_mode: 'auto_approve'
                      })
    ).perform

    conversation = channel.inbox.conversations.find_by(group_source_id: group_id)
    expect(conversation).to be_group
    expect(conversation.group_title).to eq('Support')
    expect(conversation.contact).to be_nil
    expect(conversation.additional_attributes.dig('whatsapp_group', 'invite_link')).to eq('https://chat.whatsapp.com/LINKID')
  end

  it 'adds a participant from the documented participants webhook' do
    conversation = channel.inbox.conversations.create!(
      account: channel.account,
      group: true,
      group_source_id: group_id,
      group_title: 'Support'
    )

    described_class.new(
      inbox: channel.inbox,
      params: payload('group_participants_update', {
                        group_id: group_id,
                        type: 'group_participants_add',
                        reason: 'invite_link',
                        added_participants: [{
                          wa_id: '15551230001',
                          user_id: 'US.13491208655302741918',
                          username: 'ana'
                        }]
                      })
    ).perform

    expect(conversation.reload.contact&.phone_number).to eq('+15551230001')
    expect(conversation.contact.name).to eq('ana')
  end

  it 'does nothing when groups are disabled' do
    channel.provider_config = channel.provider_config.merge('groups_enabled' => false)
    channel.save!(validate: false)

    described_class.new(
      inbox: channel.inbox,
      params: payload('group_lifecycle_update', { type: 'group_create', group_id: group_id, subject: 'Support' })
    ).perform

    expect(channel.inbox.conversations.count).to eq(0)
  end
end
