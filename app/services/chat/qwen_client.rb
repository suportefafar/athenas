require "net/http"
require "json"

module Chat
  class QwenClient
    class Unavailable < StandardError; end

    def initialize(api_key: ENV["QWEN_API_KEY"], base_url: ENV.fetch("QWEN_BASE_URL", "http://150.164.110.3:8080/v1"),
      model: ENV.fetch("QWEN_MODEL", "qwen3.5-9b"))
      @api_key = api_key
      @model = model
      @base = URI(base_url)
      unless %w[http https].include?(@base.scheme) && @base.host.present? && @base.userinfo.nil? && @base.query.nil? && @base.fragment.nil?
        raise Unavailable, "O servidor do assistente está configurado incorretamente."
      end
    rescue URI::InvalidURIError
      raise Unavailable, "O servidor do assistente está configurado incorretamente."
    end

    def call(messages:, tools: nil, tool_choice: nil, max_tokens: 1_600)
      raise Unavailable, "O assistente ainda não está configurado neste ambiente." if @api_key.blank? || @model.blank?

      uri = URI.join(@base.to_s.sub(%r{/+\z}, "") + "/", "chat/completions")
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{@api_key}")
      payload = { model: @model, messages: messages, temperature: 0.1, max_tokens: max_tokens }
      # The analysis pipeline requests an answer, not an unbounded hidden thought
      # stream. In particular the planner must fit in its small output budget.
      payload[:chat_template_kwargs] = { enable_thinking: false } if @model.downcase.include?("qwen")
      payload[:tools] = tools if tools
      payload[:tool_choice] = tool_choice if tool_choice
      request.body = JSON.generate(payload)
      response = Net::HTTP.start(uri.host, uri.port, nil, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 150) do |http|
        http.request(request)
      end
      raise Unavailable, "O servidor do assistente não respondeu corretamente (HTTP #{response.code})." unless response.is_a?(Net::HTTPSuccess)
      raise Unavailable, "A resposta do assistente excedeu o limite." if response.body.bytesize > 2.megabytes

      parsed = JSON.parse(response.body)
      choice = parsed.dig("choices", 0)
      message = choice&.dig("message")
      raise Unavailable, "O assistente retornou uma resposta inválida." unless message.is_a?(Hash)
      raise Unavailable, "A análise excedeu o limite de saída. Reduza o escopo da pergunta." if choice["finish_reason"] == "length"
      message.slice("role", "content", "tool_calls").merge("usage" => parsed["usage"], "finish_reason" => choice["finish_reason"])
    rescue IOError, SystemCallError, Timeout::Error, JSON::ParserError, NoMethodError
      raise Unavailable, "O servidor do assistente está indisponível no momento."
    end
  end
end
