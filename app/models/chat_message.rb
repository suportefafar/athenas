class ChatMessage < ApplicationRecord
  belongs_to :chat_conversation, touch: true

  validates :role, inclusion: { in: %w[user assistant] }
  validates :content, presence: true
  validates :content, length: { maximum: 2_000 }, if: -> { role == "user" }
end
