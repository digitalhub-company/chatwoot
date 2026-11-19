require 'rails_helper'

describe Whatsapp::IncomingMessageWhatsappCloudService, '#perform' do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:group_id) { 'Y2FwaV9ncm91cDoxNzA1NTU1MDEzOToxMjAzNjM0MDQ2OTQyMzM4MjAZD' }

  before do
    channel.provider_config = channel.provider_config.merge('groups_enabled' => true)
    channel.save!(validate: false)
  end

  after do
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  def group_message_params(from:, name:, message_id:, body:)
    {
      object: 'whatsapp_business_account',
      entry: [{ changes: [{ field: 'messages', value: group_message_value(from, name, message_id, body) }] }]
    }.with_indifferent_access
  end

  def group_message_value(from, name, message_id, body)
    {
      messaging_product: 'whatsapp',
      metadata: { display_phone_number: channel.phone_number, phone_number_id: channel.provider_config['phone_number_id'] },
      contacts: [{ profile: { name: name }, wa_id: from, user_id: "US.#{from}" }],
      messages: [{
        from: from, from_user_id: "US.#{from}", group_id: group_id, id: message_id,
        timestamp: '1755548877', text: { body: body }, type: 'text'
      }]
    }
  end

  it 'creates one group conversation and shows each participant as the message sender' do
    described_class.new(
      inbox: channel.inbox,
      params: group_message_params(from: '15551230001', name: 'Ana', message_id: 'wamid.group.1', body: 'Olá grupo')
    ).perform
    described_class.new(
      inbox: channel.inbox,
      params: group_message_params(from: '15551230002', name: 'Bruno', message_id: 'wamid.group.2', body: 'Oi Ana')
    ).perform

    conversation = channel.inbox.conversations.find_by!(group_source_id: group_id)
    expect(conversation).to be_group
    expect(channel.inbox.conversations.where(group: false).count).to eq(0)
    expect(conversation.messages.incoming.map { |message| [message.sender.name, message.content] }).to eq(
      [['Ana', 'Olá grupo'], ['Bruno', 'Oi Ana']]
    )
    expect(conversation.contact.name).to eq('Ana')
    expect(conversation.group_contacts.map { |membership| membership.contact.name }).to eq(['Bruno'])
  end

  it 'ignores group messages when the inbox flag is off and still accepts a 1:1 message' do
    channel.provider_config = channel.provider_config.merge('groups_enabled' => false)
    channel.save!(validate: false)

    described_class.new(
      inbox: channel.inbox,
      params: group_message_params(from: '15551230001', name: 'Ana', message_id: 'wamid.group.1', body: 'Olá grupo')
    ).perform

    expect(channel.inbox.conversations.count).to eq(0)

    described_class.new(
      inbox: channel.inbox,
      params: {
        object: 'whatsapp_business_account',
        entry: [{
          changes: [{
            value: {
              contacts: [{ profile: { name: 'Ana' }, wa_id: '15551230001' }],
              messages: [{
                from: '15551230001',
                id: 'wamid.direct.1',
                timestamp: '1755548877',
                text: { body: 'Oi' },
                type: 'text'
              }]
            }
          }]
        }]
      }.with_indifferent_access
    ).perform

    conversation = channel.inbox.conversations.last
    expect(conversation.group?).to be(false)
    expect(conversation.messages.last.content).to eq('Oi')
  end
end
