class ChatConversation < ApplicationRecord
  belongs_to :user
  has_many :chat_messages, dependent: :delete_all

  validates :title, presence: true, length: { maximum: 100 }
end
