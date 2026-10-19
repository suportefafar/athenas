require "net/http"
require "json"

module Embeddings
  class OllamaClient
    class Unavailable < StandardError; end
    DIMENSIONS = 1024

    def initialize(base_url: ENV.fetch("OLLAMA_BASE_URL", "http://localhost:11434"), retries: 2)
      @base = URI(base_url)
      @retries = retries
      # Only the operator-configured local service is used; no redirects or remote fallback.
      raise ArgumentError, "Ollama requer URL HTTP(S) sem credenciais" unless %w[http https].include?(@base.scheme) && @base.userinfo.nil?
      raise ArgumentError, "EMBEDDING_DIMENSIONS deve ser 1024; outra dimensão exige migration e reindexação." unless ENV.fetch("EMBEDDING_DIMENSIONS", DIMENSIONS).to_i == DIMENSIONS
    end

    def call(text)
      attempts = 0
      begin
        uri = @base + "/api/embed"
        request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
        request.body = JSON.generate(model: ENV.fetch("EMBEDDING_MODEL", "bge-m3"), input: text, truncate: false)
        response = Net::HTTP.start(uri.host, uri.port, nil, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 60) { |http| http.request(request) }
        raise Unavailable, "Serviço local de embeddings indisponível." unless response.is_a?(Net::HTTPSuccess)
        vector = JSON.parse(response.body).fetch("embeddings").first
        unless vector.is_a?(Array) && vector.size == DIMENSIONS && vector.all? { |v| v.is_a?(Numeric) && v.finite? } && vector.any? { |v| v != 0 }
          raise Unavailable, "O modelo local retornou embedding inválido ou dimensão incompatível."
        end
        vector
      rescue Unavailable, IOError, SystemCallError, Timeout::Error, JSON::ParserError, KeyError, NoMethodError
        attempts += 1
        retry if attempts <= @retries
        raise Unavailable, "Serviço local de embeddings indisponível ou incompatível."
      end
    end

    def self.sql_vector(vector)
      unless vector.size == DIMENSIONS && vector.all? { |v| v.is_a?(Numeric) && v.finite? }
        raise Unavailable, "Embedding inválido."
      end
      "[#{vector.join(',')}]"
    end
  end
end
