module Search
  class SemanticSearch
    def initialize(client: Embeddings::OllamaClient.new)
      @client = client
    end

    def call(query, page:)
      vector = ApplicationRecord.connection.quote(Embeddings::OllamaClient.sql_vector(@client.call(query)))
      threshold = Float(ENV.fetch("SEMANTIC_MIN_SIMILARITY", "0.60")).clamp(-1, 1)
      # Exact cosine search, one best matching chunk score per lot.
      scores = LotChunk.joins(:lot).where(lots: { status: %w[ready partial] }).where.not(embedding: nil)
        .group(:lot_id).having("MAX(1 - (embedding <=> #{vector}::vector)) >= ?", threshold)
        .select("lot_id, MAX(1 - (embedding <=> #{vector}::vector)) AS similarity")
      scope = Lot.joins("JOIN (#{scores.to_sql}) scores ON scores.lot_id = lots.id")
        .order(Arel.sql("scores.similarity DESC, lots.created_at DESC, lots.id DESC"))
      Result.new(lots: scope.limit(20).offset((page - 1) * 20).to_a, total: scope.count, page: page, mode: :semantic)
    end
  end
end
