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
      @responses.shift || raise("Resposta não prevista")
    end
  end

  test "pesquisa o livro pelo nome e analisa o texto completo mesmo sem embeddings" do
    lot = create_lot(name: "Bitcoin para programadores.pdf", extracted_text: "Introdução\n#{'explicação ' * 200}\nÚltima seção: carteiras e assinaturas.")
    client = FakeClient.new(plan("Bitcoin"), answer("O livro explica carteiras e assinaturas [1]."))

    result = Chat::Assistant.new(client: client).call(prompt: "E o livro sobre BTC? Me dê um resumo dele")

    assert_equal [ lot.id ], result.sources.map { |source| source["lot_id"] }
    assert_equal "full_text", result.sources.first["coverage"]
    assert_includes client.requests.last[:messages].last[:content], "Última seção: carteiras e assinaturas."
    assert_includes result.answer, "assinaturas"
    assert client.requests.none? { |request| request.key?(:tools) }
  end

  test "consulta pelo nome traz todos os relatórios e fontes sem duplicação" do
    10.times { |i| create_lot(name: "Ana Silva (#{i}).pdf", extracted_text: "Relatório #{i}: coordenadora do laboratório desde 2016.") }
    client = FakeClient.new(plan("Ana Silva"), answer("A coordenação começou em 2016 [1]."))
    result = Chat::Assistant.new(client: client).call(prompt: "Quais laboratórios Ana Silva coordenou?")
    assert_equal 10, result.sources.size
    assert_equal 10, result.sources.map { |source| source["lot_id"] }.uniq.size
    assert_includes client.requests.last[:messages].last[:content], "Relatório 9"
  end

  test "localização de arquivos não inicia análise de conteúdo" do
    create_lot(name: "Orçamento.pdf", extracted_text: "Texto que só deve ser lido para análise")
    client = FakeClient.new(plan("Orçamento", intent: "search"), answer("Encontrei Orçamento.pdf [1]."))
    result = Chat::Assistant.new(client: client).call(prompt: "Encontre arquivos de orçamento")
    assert_equal "excerpts", result.sources.first["coverage"]
    assert_equal 2, client.requests.size
  end

  test "reformula consulta vazia antes de desistir" do
    lot = create_lot(name: "Bitcoin.pdf", extracted_text: "Blocos e transações")
    search = Object.new
    queries = []
    search.define_singleton_method(:call) do |query|
      queries << query
      { query: query, mode: "lexical", total: query == "Bitcoin" ? 1 : 0,
        documents: query == "Bitcoin" ? [ { lot_id: lot.id, title: lot.name } ] : [] }
    end
    client = FakeClient.new(plan("BTC"), plan("Bitcoin"), answer("Blocos e transações [1]."))
    result = Chat::Assistant.new(client: client, file_search: search).call(prompt: "Resuma o livro de BTC")
    assert_equal [ "BTC", "Bitcoin" ], queries
    assert_equal lot.id, result.sources.first["lot_id"]
    assert_includes client.requests[1][:messages].last[:content], "Pesquisas anteriores"
  end

  test "essa fonte e dele reabrem o documento anterior sem novo planejamento" do
    lot = create_lot(name: "Bitcoin.pdf", extracted_text: "Texto completo sobre carteiras")
    client = FakeClient.new(answer("Resumo [1]."))
    history = [ ChatMessage.new(role: "assistant", content: "Encontrei [1].",
      sources: [ { "reference" => 1, "lot_id" => lot.id, "title" => lot.name } ]) ]
    result = Chat::Assistant.new(client: client).call(prompt: "Me dê um resumo dele", history: history)
    assert_equal 1, client.requests.size
    assert_equal lot.id, result.sources.first["lot_id"]
    assert_includes client.requests.last[:messages].last[:content], "Texto completo"
  end

  test "cada documento usa todas as fontes anteriores" do
    lots = 2.times.map { |i| create_lot(name: "Relatório #{i}.pdf", extracted_text: "Ensino e pesquisa") }
    history = [ ChatMessage.new(role: "assistant", content: "Duas fontes", sources: lots.each_with_index.map { |lot, i| { "reference" => i + 1, "lot_id" => lot.id, "title" => lot.name } }) ]
    client = FakeClient.new(answer("Estimativa temática: ensino 50%, pesquisa 50% [1][2]."))
    result = Chat::Assistant.new(client: client).call(prompt: "Qual a porcentagem de assuntos em cada documento?", history: history)
    assert_equal lots.map(&:id), result.sources.map { |source| source["lot_id"] }
  end

  test "catálogo inclui todos os documentos até o limite sem exigir termos" do
    3.times { |i| create_lot(name: "Documento #{i}", extracted_text: "Assunto #{i}") }
    response = { "content" => { intent: "analysis", queries: [], all_documents: true }.to_json }
    client = FakeClient.new(response, answer("Distribuição estimada [1][2][3]."))
    result = Chat::Assistant.new(client: client).call(prompt: "Analise os assuntos de todos os documentos do acervo")
    assert_equal 3, result.sources.size
  end

  test "resposta com chamada textual de ferramenta é refeita sem exibir XML" do
    create_lot(name: "Bitcoin.pdf", extracted_text: "Transações")
    client = FakeClient.new(plan("Bitcoin"), answer("Vou recuperar <tool_call>não executado</tool_call>"), answer("Transações [1]."))
    result = Chat::Assistant.new(client: client).call(prompt: "Resuma Bitcoin")
    assert_equal "Transações [1].", result.answer
    assert_equal 3, client.requests.size
  end

  test "pesquisa adicional após resposta sem evidência pode encontrar outro documento" do
    first = create_lot(name: "Ana Silva.pdf", extracted_text: "Dados cadastrais")
    second = create_lot(name: "Portaria de coordenação.pdf", extracted_text: "Ana Silva coordena o laboratório de Alimentos desde 2020")
    searches = []
    search = Object.new
    search.define_singleton_method(:call) do |query|
      searches << query
      lot = query == "Ana Silva" ? first : second
      { query: query, mode: "lexical", total: 1, documents: [ { lot_id: lot.id, title: lot.name } ] }
    end
    client = FakeClient.new(plan("Ana Silva"), answer("Não localizei a coordenação no texto disponível [1]."),
      plan("Portaria coordenação"), answer("Laboratório de Alimentos desde 2020 [2]."))
    result = Chat::Assistant.new(client: client, file_search: search).call(prompt: "Quais laboratórios Ana Silva coordenou?")
    assert_equal [ "Ana Silva", "Portaria coordenação" ], searches
    assert_equal [ first.id, second.id ], result.sources.map { |source| source["lot_id"] }
    assert_includes result.answer, "2020"
  end

  private

  def plan(query, intent: "analysis")
    { "content" => { intent: intent, queries: [ query ], all_documents: false }.to_json }
  end

  def answer(text)
    { "role" => "assistant", "content" => text }
  end
end
