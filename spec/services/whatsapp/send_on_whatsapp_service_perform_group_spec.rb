require 'rails_helper'

describe Whatsapp::SendOnWhatsappService, '#perform' do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:contact) { create(:contact, account: channel.account, phone_number: '+15551230001') }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, contact: contact, source_id: '15551230001') }
  let(:group_id) { 'Y2FwaV9ncm91cDoxNzA1NTU1MDEzOToxMjAzNjM0MDQ2OTQyMzM4MjAZD' }
  let(:conversation) do
    create(:conversation, account: channel.account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox).tap do |record|
      record.update!(group: true, group_title: 'Support', group_source_id: group_id)
    end
  end

  before do
    channel.provider_config = channel.provider_config.merge('groups_enabled' => true)
    channel.save!(validate: false)
    create(:message, conversation: conversation, account: channel.account, inbox: channel.inbox, message_type: :incoming, sender: contact)
  end

  it 'sends the agent reply to the group id with recipient_type group' do
    stub = stub_request(:post, "https://graph.facebook.com/v22.0/#{channel.provider_config['phone_number_id']}/messages")
           .with(body: hash_including(
             'messaging_product' => 'whatsapp',
             'recipient_type' => 'group',
             'to' => group_id,
             'type' => 'text',
             'text' => { 'body' => 'Resposta do agente' }
           ))
           .to_return(status: 200, body: { messages: [{ id: 'wamid.outbound.1' }] }.to_json, headers: { 'Content-Type' => 'application/json' })

    message = create(
      :message,
      conversation: conversation,
      account: channel.account,
      inbox: channel.inbox,
      message_type: :outgoing,
      content: 'Resposta do agente'
    )

    described_class.new(message: message).perform

    expect(stub).to have_been_requested
    expect(message.reload.source_id).to eq('wamid.outbound.1')
  end

  it 'does not call Meta for an interactive group message' do
    message = create(
      :message,
      conversation: conversation,
      account: channel.account,
      inbox: channel.inbox,
      message_type: :outgoing,
      content_type: :input_select,
      content: 'Escolha',
      content_attributes: { items: [{ title: 'Sim', value: 'yes' }] }
    )

    described_class.new(message: message).perform

    expect(message.reload.status).to eq('failed')
    expect(message.external_error).to eq(I18n.t('errors.whatsapp.group_interactive_unsupported'))
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'does not send when groups are disabled on the inbox' do
    channel.provider_config = channel.provider_config.merge('groups_enabled' => false)
    channel.save!(validate: false)
    message = create(
      :message,
      conversation: conversation,
      account: channel.account,
      inbox: channel.inbox,
      message_type: :outgoing,
      content: 'Resposta do agente'
    )

    described_class.new(message: message).perform

    expect(message.reload.status).to eq('failed')
    expect(message.external_error).to eq(I18n.t('errors.whatsapp.groups_disabled'))
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end
end
