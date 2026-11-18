require 'rails_helper'

describe Whatsapp::Groups::Client do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:client) { described_class.new(channel: channel) }
  let(:phone_number_id) { channel.provider_config['phone_number_id'] }
  let(:group_id) { 'Y2FwaV9ncm91cDoxNzA1NTU1MDEzOToxMjAzNjM0MDQ2OTQyMzM4MjAZD' }

  before do
    stub_request(:post, "https://graph.facebook.com/v22.0/#{phone_number_id}/groups")
      .with(
        headers: { 'Authorization' => "Bearer #{channel.provider_config['api_key']}" },
        body: hash_including(
          'messaging_product' => 'whatsapp',
          'subject' => 'Support',
          'description' => 'Orders',
          'join_approval_mode' => 'auto_approve'
        )
      )
      .to_return(status: 200, body: { request_id: 'req-1' }.to_json, headers: { 'Content-Type' => 'application/json' })

    stub_request(:get, "https://graph.facebook.com/v22.0/#{group_id}/invite_link")
      .to_return(
        status: 200,
        body: { messaging_product: 'whatsapp', invite_link: 'https://chat.whatsapp.com/LINKID' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  it 'creates a group with the documented request body' do
    response = client.create_group(subject: 'Support', description: 'Orders', join_approval_mode: 'auto_approve')

    expect(response['request_id']).to eq('req-1')
  end

  it 'reads the group invite link' do
    response = client.invite_link(group_id)

    expect(response['invite_link']).to eq('https://chat.whatsapp.com/LINKID')
  end
end
