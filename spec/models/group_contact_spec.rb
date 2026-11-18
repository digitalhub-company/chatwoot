require 'rails_helper'

describe GroupContact do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:primary) { create(:contact, account: account) }
  let(:member) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: primary) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: primary, contact_inbox: contact_inbox).tap do |record|
      record.update!(group: true, group_title: 'Support', group_source_id: 'group-1')
    end
  end

  it 'rejects a contact who is already the primary contact' do
    record = described_class.new(conversation: conversation, contact: primary)

    expect(record).not_to be_valid
    expect(record.errors[:contact]).to include('is already the primary contact')
  end

  it 'adds another contact from the same account' do
    record = described_class.create!(conversation: conversation, contact: member)

    expect(record.account_id).to eq(account.id)
    expect(conversation.includes_contact?(member)).to be(true)
  end

  it 'promotes the first contact when the group has no primary contact' do
    empty_group = create(:conversation, account: account, inbox: inbox, contact: primary, contact_inbox: contact_inbox)
    empty_group.update!(group: true, group_source_id: 'group-empty', contact: nil, contact_inbox: nil)

    described_class.create!(conversation: empty_group, contact: member)

    expect(empty_group.reload.contact).to eq(member)
    expect(empty_group.group_contacts).to be_empty
  end
end
