class ChatMessagesController < ApplicationController
  def create
    prompt = params[:content].to_s.strip
    unless prompt.present? && prompt.length <= 2_000
      redirect_to root_path(conversation_id: params[:conversation_id]),
        flash: { chat_error: "Escreva uma pergunta de até 2.000 caracteres.", failed_prompt: prompt }
      return
    end

    conversation = if params[:conversation_id].present?
      current_user.chat_conversations.find(params[:conversation_id])
    else
      current_user.chat_conversations.create!(title: prompt.truncate(100))
    end
    conversation.update!(title: prompt.truncate(100)) if conversation.chat_messages.empty?
    history = conversation.chat_messages.order(:created_at, :id).last(8)
    result = Chat::Assistant.new.call(prompt: prompt, history: history)
    conversation.chat_messages.transaction do
      conversation.chat_messages.create!(role: "user", content: prompt)
      conversation.chat_messages.create!(role: "assistant", content: result.answer,
        sources: result.sources, tool_name: result.tool_name, tool_query: result.tool_query,
        search_mode: result.search_mode)
    end
    redirect_to root_path(conversation_id: conversation.id, anchor: "ultima-resposta")
  rescue Chat::QwenClient::Unavailable => error
    redirect_to root_path(conversation_id: conversation&.id),
      flash: { chat_error: error.message, failed_prompt: prompt }
  end
end
