require "test_helper"

class ChatRetrievalToolTest < ActiveSupport::TestCase
  test "resumo contextual recupera trechos distribuídos de um documento específico" do
    lot = create_lot(name: "Bitcoin.pdf", page_count: 20)
    other = create_lot(name: "Outro.pdf")
    20.times { |position| lot.lot_chunks.create!(position: position, text: "Trecho #{position}") }
    other.lot_chunks.create!(position: 0, text: "Texto de outro arquivo")

    result = Chat::RetrievalTool.new.call("Resuma essa fonte", lot_id: lot.id, overview: true)
    document = result[:documents].sole

    assert_equal "document", result[:mode]
    assert_equal lot.id, document[:lot_id]
    assert_equal 16, document[:sampled_chunks]
    assert_equal 20, document[:total_chunks]
    assert_equal 1, document[:excerpts].first[:position]
    assert_equal 20, document[:excerpts].last[:position]
    assert document[:excerpts].all? { |excerpt| excerpt[:text].start_with?("Trecho ") }
  end

  test "combina resultados textuais e semânticos e mantém o fim do trecho e linhas vizinhas" do
    lexical_lot = create_lot(name: "Atas.pdf", extracted_text: "Comissão ética")
    text = "Comissão ética #{'informações ' * 160}\nMANDATO 2025 a 2027"
    lexical_lot.lot_chunks.create!(position: 0, text: text)
    lexical_lot.lot_chunks.create!(position: 1, text: "Nome completo da comissão na continuação")
    semantic_lot = create_lot(name: "Designação.pdf")
    semantic_lot.lot_chunks.create!(position: 0, text: "Membro do colegiado", embedding: Embeddings::OllamaClient.sql_vector(vector))
    client = Object.new
    embedding = vector
    client.define_singleton_method(:call) { |_| embedding }
    result = Chat::RetrievalTool.new(client: client).call("Comissão ética")
    assert_equal "hybrid", result[:mode]
    assert_includes result[:documents].map { |document| document[:lot_id] }, semantic_lot.id
    assert_includes result[:documents].map { |document| document[:excerpt] }, text
    assert result[:documents].any? { |document| document[:excerpt].include?("continuação") }
  end

  test "filtragem lexical não publica texto de lote em processamento" do
    lot = create_lot(status: "processing", extracted_text: "Ética")
    lot.lot_chunks.create!(position: 0, text: "Ética")
    client = Object.new
    client.define_singleton_method(:call) { |_| raise Embeddings::OllamaClient::Unavailable }
    assert_empty Chat::RetrievalTool.new(client: client).call("Ética", lot_id: lot.id)[:documents]
  end
end
