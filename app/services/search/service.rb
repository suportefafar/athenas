module Search
  class Service
    def initialize(semantic: nil)
      @semantic = semantic
    end

    def call(query, page: 1)
      page = [ page.to_i, 1 ].max
      lexical = LexicalSearch.new(query)
      unless lexical.searchable_terms?
        return Result.new(lots: [], total: 0, page: page, mode: :lexical, warning: "Digite uma consulta mais específica, com palavras pesquisáveis.")
      end
      scope = lexical.scope
      total = scope.count
      if total.positive?
        return Result.new(lots: scope.limit(20).offset((page - 1) * 20).to_a, total: total, page: page, mode: :lexical)
      end
      (@semantic || SemanticSearch.new).call(query, page: page)
    rescue Embeddings::OllamaClient::Unavailable
      Result.new(lots: [], total: 0, page: page, mode: :semantic, warning: "Nenhum resultado lexical. A busca semântica local está temporariamente indisponível.")
    end
  end
end
