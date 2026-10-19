class ChatConversationsController < ApplicationController
  def index
    @conversations = current_user.chat_conversations.order(updated_at: :desc).limit(30)
    @conversation = if params[:conversation_id].present?
      current_user.chat_conversations.find(params[:conversation_id])
    else
      @conversations.first
    end
    @messages = @conversation ? @conversation.chat_messages.order(:created_at, :id).last(40) : []
    source_ids = @messages.flat_map { |message| message.sources.map { |source| source["lot_id"] } }.compact
    @available_lot_ids = Lot.searchable.where(id: source_ids).pluck(:id).to_set
  end

  def create
    conversation = current_user.chat_conversations.create!(title: "Nova conversa")
    redirect_to root_path(conversation_id: conversation.id)
  end
end
