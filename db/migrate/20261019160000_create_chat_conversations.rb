class CreateChatConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :chat_conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.timestamps
    end
    add_index :chat_conversations, [ :user_id, :updated_at ]

    create_table :chat_messages do |t|
      t.references :chat_conversation, null: false, foreign_key: { on_delete: :cascade }
      t.string :role, null: false
      t.text :content, null: false
      t.jsonb :sources, null: false, default: []
      t.string :tool_name
      t.string :tool_query
      t.string :search_mode
      t.timestamps
    end
    add_index :chat_messages, [ :chat_conversation_id, :created_at ]
    add_check_constraint :chat_messages, "role IN ('user', 'assistant')", name: "valid_chat_message_role"
  end
end
