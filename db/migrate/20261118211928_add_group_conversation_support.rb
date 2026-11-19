class AddGroupConversationSupport < ActiveRecord::Migration[7.1]
  def change
    add_column :conversations, :group, :boolean, default: false, null: false
    add_column :conversations, :group_source_id, :string
    add_column :conversations, :group_title, :string

    add_index :conversations, [:inbox_id, :group_source_id],
              unique: true,
              where: 'group_source_id IS NOT NULL',
              name: 'index_conversations_on_inbox_id_and_group_source_id'

    create_table :group_contacts do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.bigint :contact_id, null: false

      t.timestamps
    end

    add_index :group_contacts, :account_id
    add_index :group_contacts, :conversation_id
    add_index :group_contacts, :contact_id
    add_index :group_contacts, [:conversation_id, :contact_id],
              unique: true,
              name: 'index_group_contacts_on_conversation_and_contact'
  end
end
