require "test_helper"

class ChatAssistantTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :requests

    def initialize(*responses)
      @responses = responses
      @requests = []
    end

    def call(**arguments)
      @requests << arguments
      @responses.shift
    end
  end

  test "usa a pesquisa existente quando o modelo pede arquivos por palavra" do
    client = FakeClient.new(
      { "role" => "assistant", "content" => nil, "tool_calls" => [ tool_call("search_files", "orçamento") ] },
      { "role" => "assistant", "content" => "Encontrei o orçamento no documento [1]." }
    )
    search = Minitest::Mock.new
    search.expect(:call, { mode: "lexical", query: "orçamento", total: 1,
      documents: [ { reference: 1, lot_id: 42, title: "Orçamento.pdf", excerpt: "Orçamento anual" } ] }, [ "orçamento" ])

    result = Chat::Assistant.new(client: client, file_search: search).call(prompt: "Encontre arquivos sobre orçamento")

    assert_equal "search_files", result.tool_name
    assert_equal "orçamento", result.tool_query
    assert_equal 42, result.sources.first["lot_id"]
    assert_equal "Encontrei o orçamento no documento [1].", result.answer
    assert_equal "tool", client.requests.last[:messages].last[:role]
    search.verify
  end

  test "recupera trechos para uma pergunta analítica" do
    client = FakeClient.new(
      { "role" => "assistant", "content" => nil, "tool_calls" => [ tool_call("retrieve_excerpts", "relação entre entidades") ] },
      { "role" => "assistant", "content" => "As entidades aparecem juntas no trecho [1]." }
    )
    retrieval = Minitest::Mock.new
    retrieval.expect(:call, { mode: "semantic", query: "relação entre entidades",
      documents: [ { reference: 1, lot_id: 7, title: "Ata.txt", position: 2, excerpt: "Entidade A e B" } ] }, [ "relação entre entidades" ])

    result = Chat::Assistant.new(client: client, retrieval: retrieval).call(prompt: "Qual a relação entre as entidades?")

    assert_equal "retrieve_excerpts", result.tool_name
    assert_equal 2, result.sources.first["position"]
    assert_equal "As entidades aparecem juntas no trecho [1].", result.answer
    retrieval.verify
  end

  private

  def tool_call(name, query)
    { "id" => "tool-1", "type" => "function", "function" => { "name" => name, "arguments" => { query: query }.to_json } }
  end
end
