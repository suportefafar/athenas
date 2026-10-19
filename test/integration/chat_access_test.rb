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
end
