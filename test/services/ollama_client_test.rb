require "test_helper"
class OllamaClientTest < ActiveSupport::TestCase
  test "usa endpoint local e valida dimensão" do
    request = stub_request(:post, "http://localhost:11434/api/embed").with do |req|
      JSON.parse(req.body).slice("model", "input", "truncate") == { "model" => "bge-m3", "input" => "consulta", "truncate" => false }
    end.to_return(body: { embeddings: [ vector ] }.to_json)
    assert_equal vector, Embeddings::OllamaClient.new.call("consulta")
    assert_requested request, times: 1
  end

  test "retries limitados e sem serviço externo" do
    request = stub_request(:post, "http://localhost:11434/api/embed").to_timeout
    assert_raises(Embeddings::OllamaClient::Unavailable) { Embeddings::OllamaClient.new.call("consulta") }
    assert_requested request, times: 3
  end

  test "dimensão incorreta resposta zero e redirecionamento são recusados" do
    [ [ 1, 2 ], Array.new(1024, 0), [ Float::INFINITY ] ].each do |invalid|
      stub_request(:post, "http://localhost:11434/api/embed").to_return(body: { embeddings: [ invalid ] }.to_json(allow_nan: true))
      assert_raises(Embeddings::OllamaClient::Unavailable) { Embeddings::OllamaClient.new(retries: 0).call("consulta") }
    end
    stub_request(:post, "http://localhost:11434/api/embed").to_return(status: 302, headers: { "Location" => "https://external.example/" })
    assert_raises(Embeddings::OllamaClient::Unavailable) { Embeddings::OllamaClient.new(retries: 0).call("consulta") }
  end
end
