require "test_helper"

class QwenClientTest < ActiveSupport::TestCase
  test "desativa pensamento para não consumir a saída do planejamento" do
    request = stub_request(:post, "http://qwen.test/v1/chat/completions").with do |req|
      body = JSON.parse(req.body)
      body.dig("chat_template_kwargs", "enable_thinking") == false && body["max_tokens"] == 700
    end.to_return(body: { choices: [ { finish_reason: "stop", message: { role: "assistant", content: "{}" } } ], usage: { total_tokens: 30 } }.to_json)
    result = Chat::QwenClient.new(api_key: "test", base_url: "http://qwen.test/v1").call(messages: [], max_tokens: 700)
    assert_equal 30, result.dig("usage", "total_tokens")
    assert_requested request
  end

  test "não publica resposta cortada por limite de tokens" do
    stub_request(:post, "http://qwen.test/v1/chat/completions").to_return(body: { choices: [ { finish_reason: "length", message: { content: "Resposta interrompida" } } ] }.to_json)
    error = assert_raises(Chat::QwenClient::Unavailable) { Chat::QwenClient.new(api_key: "test", base_url: "http://qwen.test/v1").call(messages: []) }
    assert_includes error.message, "limite de saída"
  end
end
