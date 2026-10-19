require "test_helper"
class SearchTest < ActiveSupport::TestCase
  setup { @user = create_user }

  test "AND com palavras em campos diferentes e acentos normalizados" do
    lot = create_lot(name: "Relatório anual", extracted_text: "O resultado financeiro está aprovado", metadata_search_text: "2025")
    create_lot(name: "Relatório", extracted_text: "financeiro", metadata_search_text: "2024")
    result = Search::Service.new(semantic: Object.new).call("relatorio financeiro 2025")
    assert_equal [ lot.id ], result.lots.map(&:id)
    assert_equal :lexical, result.mode
  end

  test "stopwords e flexões portuguesas" do
    lot = create_lot(extracted_text: "Afastamentos para capacitação")
    result = Search::Service.new(semantic: Object.new).call("afastamento para capacitacao")
    assert_equal [ lot.id ], result.lots.map(&:id)
    empty = Search::Service.new(semantic: Object.new).call("para de e")
    assert_equal 0, empty.total
    assert_match "específica", empty.warning
  end

  test "conteúdo pesa mais que nome e metadados" do
    metadata = create_lot(metadata_search_text: "financeiro", created_at: 1.minute.ago)
    name = create_lot(name: "Financeiro", created_at: 2.minutes.ago)
    content = create_lot(extracted_text: "financeiro", created_at: 3.minutes.ago)
    result = Search::Service.new.call("financeiro")
    assert_equal [ content.id, name.id, metadata.id ], result.lots.map(&:id)
  end

  test "termos distribuídos no conteúdo e resultado único mesmo com muitos chunks" do
    lot = create_lot(extracted_text: "licença " + "palavra " * 500 + "capacitação")
    3.times { |index| add_chunk(lot, position: index) }
    assert_equal [ lot.id ], Search::Service.new.call("licença capacitação").lots.map(&:id)
  end

  test "pending processing failed rejected nunca aparecem" do
    %w[pending processing failed rejected].each { |status| create_lot(status: status, extracted_text: "publicação") }
    partial = create_lot(status: "partial", extracted_text: "publicação")
    assert_equal [ partial.id ], Search::Service.new.call("publicação").lots.map(&:id)
  end

  test "semântica só executa quando zero lexical e agrega por lote com limiar" do
    lot = create_lot
    3.times { |index| add_chunk(lot, position: index) }
    irrelevant = create_lot
    add_chunk(irrelevant, embedding: vector(1))
    hidden = create_lot(status: "processing")
    add_chunk(hidden)
    client = Minitest::Mock.new
    client.expect :call, vector, [ "inexistente" ]
    semantic = Search::SemanticSearch.new(client: client)
    result = Search::Service.new(semantic: semantic).call("inexistente")
    assert_equal :semantic, result.mode
    assert_equal 1, result.total
    assert_equal [ lot.id ], result.lots.map(&:id)
    client.verify
  end

  test "qualquer match lexical impede a chamada semântica inclusive página fora do intervalo" do
    create_lot(extracted_text: "orçamento")
    result = Search::Service.new(semantic: Object.new).call("orçamento", page: 8)
    assert_equal 1, result.total
    assert_empty result.lots
    assert_equal :lexical, result.mode
  end

  test "paginação estável por relevância recência e id" do
    time = Time.current
    23.times { create_lot(extracted_text: "orçamento", created_at: time) }
    first = Search::Service.new.call("orçamento")
    second = Search::Service.new.call("orçamento", page: 2)
    assert_equal 23, first.total
    assert_equal 20, first.lots.size
    assert_equal 3, second.lots.size
    assert_empty first.lots.map(&:id) & second.lots.map(&:id)
    assert_equal Lot.order(id: :desc).pluck(:id), (first.lots + second.lots).map(&:id)
  end

  test "falha do modelo apresenta indisponibilidade" do
    client = Object.new
    def client.call(*) = raise Embeddings::OllamaClient::Unavailable
    result = Search::Service.new(semantic: Search::SemanticSearch.new(client: client)).call("nada")
    assert_match "temporariamente indisponível", result.warning
  end
  test "capacidade máxima do tsvector gera partial com índice utilizável de nome" do
    text = (1..100_000).map { |i| "termo#{i.to_s(36)}" }.join(" ")
    lot = create_lot(name: "Acervo volumoso", extracted_text: text)
    assert_equal "partial", lot.reload.status
    assert_match "capacidade", lot.processing_warnings.last
    assert_equal [ lot.id ], Search::Service.new.call("acervo volumoso").lots.map(&:id)
  end
end
