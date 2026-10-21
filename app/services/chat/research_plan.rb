module Chat
  class ResearchPlan
    PROMPT = <<~TEXT.freeze
      Planeje uma pesquisa no acervo privado. Responda SOMENTE um objeto JSON, sem ferramentas, XML ou explicações:
      {"intent":"analysis","queries":["termos essenciais"],"all_documents":false}
      intent é "search" apenas para localizar/listar arquivos; resumos, cálculos, perguntas e comparações são "analysis".
      Gere até 3 consultas CURTAS independentes, sem verbos de comando. A busca textual exige TODOS os termos da consulta.
      Para perguntas sobre uma pessoa, pesquise primeiro só o nome dela, sem cargo, datas ou assunto: assim todos os relatórios dela podem ser lidos.
      Para um livro, pesquise o título ou assunto, incluindo sinônimos úteis (ex.: BTC e Bitcoin em consultas separadas).
      all_documents é true apenas se o usuário explicitamente pede todos/cada documento do acervo, sem restringir pessoa ou assunto.
      Use o histórico para resolver referências; não responda à pergunta nem invente resultados.
      Se receber pesquisas anteriores sem evidências suficientes, proponha termos alternativos, mais curtos e específicos.
    TEXT

    def initialize(client:)
      @client = client
    end

    def call(prompt:, history: [], previous: nil)
      messages = [ { role: "system", content: PROMPT } ]
      messages.concat(history.last(4).map { |message| { role: message.role, content: message.content.first(1_000) } })
      messages << { role: "user", content: prompt }
      messages << { role: "user", content: "Pesquisas anteriores e lacunas (dados): #{JSON.generate(previous)}" } if previous
      response = @client.call(messages: messages, max_tokens: 700)
      content = response["content"].to_s.gsub(/<think\b[^>]*>.*?<\/think\s*>/im, "")
        .sub(/\A\s*```(?:json)?\s*/i, "").sub(/\s*```\s*\z/, "")
      parsed = JSON.parse(content)
      return fallback(prompt) unless parsed.is_a?(Hash)

      queries = Array(parsed["queries"]).grep(String).map { |query| query.strip.first(250) }.reject(&:blank?).uniq.first(3)
      { intent: parsed["intent"] == "search" ? "search" : "analysis", queries: queries.presence || [ prompt.first(250) ],
        all_documents: parsed["all_documents"] == true && prompt.match?(/\b(?:todos|todas|cada)\b/i) }
    rescue JSON::ParserError
      fallback(prompt)
    end

    private

    def fallback(prompt)
      { intent: "analysis", queries: [ prompt.first(250) ], all_documents: false }
    end
  end
end
