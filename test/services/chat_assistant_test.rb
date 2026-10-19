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

  class FakeRetrieval
    attr_reader :requests

    def initialize(result)
      @result = result
      @requests = []
    end

    def call(query, **options)
      @requests << [ query, options ]
      @result
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

  test "resumo de essa fonte recupera o documento da resposta anterior" do
    client = FakeClient.new({ "role" => "assistant", "content" => "Resumo dos trechos do documento [1]." })
    retrieval = FakeRetrieval.new(mode: "document", query: "Sobre o que essa fonte trata? Resuma em dois parágrafos",
      documents: [ { reference: 1, lot_id: 42, title: "Bitcoin.pdf",
        excerpts: [ { position: 1, text: "Introdução ao Bitcoin" } ] } ])
    history = [
      ChatMessage.new(role: "user", content: "Quais documentos falam de BTC?"),
      ChatMessage.new(role: "assistant", content: "Encontrei Bitcoin.pdf [1].",
        sources: [ { "reference" => 1, "lot_id" => 42, "title" => "Bitcoin.pdf" } ]),
      ChatMessage.new(role: "user", content: "Sobre o que essa fonte trata?"),
      ChatMessage.new(role: "assistant", content: "Não encontrei evidências suficientes.")
    ]

    result = Chat::Assistant.new(client: client, retrieval: retrieval).call(
      prompt: "Sobre o que essa fonte trata? Resuma em dois parágrafos", history: history)

    assert_equal [ [ "Sobre o que essa fonte trata? Resuma em dois parágrafos", { lot_id: 42, overview: true } ] ], retrieval.requests
    assert_equal 1, client.requests.size
    assert_equal 42, result.sources.first["lot_id"]
    assert_equal "Resumo dos trechos do documento [1].", result.answer
  end

  private

  def tool_call(name, query)
    { "id" => "tool-1", "type" => "function", "function" => { "name" => name, "arguments" => { query: query }.to_json } }
  end
end
