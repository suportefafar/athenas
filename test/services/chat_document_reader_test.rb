require "test_helper"

class ChatDocumentReaderTest < ActiveSupport::TestCase
  test "texto completo preserva linhas colunas e fim do documento sem depender de chunks" do
    text = "Comissão   Início    Fim\nÉtica      2025      2027\n#{'Detalhes ' * 200}\nLaboratório de Alimentos"
    lot = create_lot(extracted_text: text)
    result = Chat::DocumentReader.new(client: Object.new).call([ lot.id ], question: "Quais comissões?")
    assert_equal text, result[:documents].sole[:text]
    assert_equal "full_text", result[:documents].sole[:coverage]
  end

  test "texto longo é analisado inteiro em partes sem amostragem e sem sobreposição" do
    text = "#{'a' * 3_999}\n#{'b' * 3_999}\n#{'c' * 500} FINAL"
    lot = create_lot(extracted_text: text)
    parts = []
    client = Object.new
    client.define_singleton_method(:call) do |messages:, **|
      parts << JSON.parse(messages.last[:content]).fetch("text")
      { "content" => "Evidência da parte #{parts.size}" }
    end
    document = Chat::DocumentReader.new(client: client, context_characters: 4_000).call([ lot.id ], question: "Resuma")[:documents].sole
    assert_equal text, parts.join
    assert parts.all? { |part| part.length <= 4_000 }
    assert_equal "full_text_analyzed_in_parts", document[:coverage]
    assert_equal text.length, document[:analyzed_characters]
    assert_includes document[:notes], "parte 3"
  end

  test "não lê documentos excluídos ou ainda em processamento" do
    lot = create_lot(status: "processing", extracted_text: "Não publicar")
    result = Chat::DocumentReader.new(client: Object.new).call([ lot.id ], question: "Resuma")
    assert_empty result[:documents]
    assert result[:warnings].any?
  end

  test "texto ausente é sinalizado sem alegar cobertura completa" do
    lot = create_lot(extracted_text: nil)
    document = Chat::DocumentReader.new(client: Object.new).call([ lot.id ], question: "Resuma")[:documents].sole
    assert_equal "unavailable", document[:coverage]
  end

  test "limite de trabalho deixa cobertura parcial explícita sem afirmar leitura completa" do
    lot = create_lot(extracted_text: "x" * 164_001)
    calls = 0
    client = Object.new
    client.define_singleton_method(:call) do |**|
      calls += 1
      { "content" => "Nota curta" }
    end
    document = Chat::DocumentReader.new(client: client, context_characters: 4_000).call([ lot.id ], question: "Resuma")[:documents].sole
    assert_equal 40, calls
    assert_equal "partial", document[:coverage]
    assert_equal 160_000, document[:analyzed_characters]
  end

  test "análise vazia de uma parte não é publicada como leitura completa" do
    lot = create_lot(extracted_text: "x" * 4_001)
    client = Object.new
    client.define_singleton_method(:call) { |**| { "content" => "" } }
    assert_raises(Chat::QwenClient::Unavailable) do
      Chat::DocumentReader.new(client: client, context_characters: 4_000).call([ lot.id ], question: "Resuma")
    end
  end

  test "síntese de muitas evidências respeita o orçamento e preserva fontes separadas" do
    lots = 2.times.map { |i| create_lot(name: "Relatório #{i}", extracted_text: "x" * 5_000) }
    client = Object.new
    client.define_singleton_method(:call) do |messages:, **|
      data = JSON.parse(messages.last[:content])
      { "content" => data.key?("notes") ? "Evidência condensada #{'a' * 900}" : "Evidência detalhada #{'b' * 1_400}" }
    end
    result = Chat::DocumentReader.new(client: client, context_characters: 4_000).call(lots.map(&:id), question: "Compare")
    assert_equal lots.map(&:id), result[:documents].map { |document| document[:lot_id] }
    assert result[:documents].sum { |document| document[:notes].length } <= 4_000
    assert result[:documents].all? { |document| document[:notes].include?("condensada") && document[:warnings].any? }
  end
end
