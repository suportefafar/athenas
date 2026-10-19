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
end
