require "test_helper"

class ChatResearchPlanTest < ActiveSupport::TestCase
  test "planejamento aceita apenas consultas de texto com tamanho e quantidade limitados" do
    client = Object.new
    client.define_singleton_method(:call) do |**|
      { "content" => { intent: "analysis", queries: [ "Ana", "Ana", "b" * 300, { sql: "qualquer coisa" }, "C", "D" ], all_documents: true }.to_json }
    end
    plan = Chat::ResearchPlan.new(client: client).call(prompt: "Quais laboratórios Ana coordenou?")
    assert_equal [ "Ana", "b" * 250, "C" ], plan[:queries]
    assert_equal false, plan[:all_documents]
  end

  test "XML ou JSON malformado não é executado como ferramenta" do
    client = Object.new
    client.define_singleton_method(:call) { |**| { "content" => "<tool_call><function=read_file>...</function></tool_call>" } }
    plan = Chat::ResearchPlan.new(client: client).call(prompt: "Bitcoin")
    assert_equal [ "Bitcoin" ], plan[:queries]
    assert_equal "analysis", plan[:intent]
  end
end
