require "test_helper"

class ChatAccessTest < ActionDispatch::IntegrationTest
  test "a página inicial é o chat e a pesquisa tem página própria na navegação" do
    login(create_user)

    get root_path
    assert_response :success
    assert_select "form[action='#{chat_messages_path}']"
    assert_select "nav a[href='#{search_path}']", text: "Pesquisar arquivos"

    get search_path
    assert_response :success
    assert_select "h1", text: "Pesquisar arquivos"
    assert_select "form[action='#{search_path}']"
  end

  test "cada usuário vê e escreve somente em suas conversas" do
    owner = create_user
    conversation = owner.chat_conversations.create!(title: "Conversa privada")
    other = create_user
    login(other)

    get root_path(conversation_id: conversation.id)
    assert_response :not_found

    post chat_messages_path, params: { conversation_id: conversation.id, content: "O que diz a ata?" }
    assert_response :not_found
    assert_equal 0, conversation.chat_messages.count
  end

  test "falha do assistente aparece na conversa e pode ser reenviada sem duplicar a pergunta" do
    user = create_user
    login(user)
    conversation = user.chat_conversations.create!(title: "Teste")
    prompt = "Resuma o livro de BTC"
    failing_assistant = Object.new
    def failing_assistant.call(**)
      raise Chat::QwenClient::Unavailable, "O servidor do assistente está indisponível no momento."
    end

    Chat::Assistant.stub(:new, failing_assistant) do
      post chat_messages_path, params: { conversation_id: conversation.id, content: prompt }
    end
    assert_redirected_to root_path(conversation_id: conversation.id)
    assert_equal 0, conversation.chat_messages.count

    follow_redirect!
    assert_select ".chat-message.user[data-chat-failed] .chat-bubble", text: prompt
    assert_select ".chat-message.assistant[data-chat-error] .chat-error", text: /servidor do assistente está indisponível/
    assert_select "[data-chat-retry-prompt='#{prompt}']", text: "Tentar novamente"
    assert_select ".ffds-alert", text: /servidor do assistente está indisponível/, count: 0

    successful_assistant = Object.new
    def successful_assistant.call(**)
      Chat::Assistant::Result.new(answer: "Resumo de teste", sources: [])
    end
    Chat::Assistant.stub(:new, successful_assistant) do
      post chat_messages_path, params: { conversation_id: conversation.id, content: prompt }
    end
    assert_equal ["user", "assistant"], conversation.chat_messages.order(:id).pluck(:role)
  end
end
