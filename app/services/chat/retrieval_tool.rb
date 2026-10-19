module Chat
  class RetrievalTool
    MAX_CHUNKS = 10

    def initialize(client: Embeddings::OllamaClient.new)
      @client = client
    end

    def call(query)
      chunks = semantic_chunks(query)
      mode = "semantic"
      if chunks.empty?
        chunks = lexical_chunks(query)
        mode = "lexical"
      end
      {
        mode: mode,
        query: query,
        documents: chunks.each_with_index.map do |chunk, index|
          {
            reference: index + 1,
            lot_id: chunk.lot_id,
            title: chunk.lot.name,
            position: chunk.position + 1,
            excerpt: chunk.text.first(1_250)
          }
        end
      }
    end

    private

    def semantic_chunks(query)
      vector = Embeddings::OllamaClient.sql_vector(@client.call(query))
      quoted = ApplicationRecord.connection.quote(vector)
      threshold = Float(ENV.fetch("CHAT_MIN_SIMILARITY", "0.48")).clamp(-1, 1)
      candidates = LotChunk.includes(:lot).joins(:lot)
        .where(lots: { status: %w[ready partial] }).where.not(embedding: nil)
        .where("1 - (lot_chunks.embedding <=> #{quoted}::vector) >= ?", threshold)
        .order(Arel.sql("lot_chunks.embedding <=> #{quoted}::vector"))
        .limit(40).to_a
      counts = Hash.new(0)
      candidates.select { |chunk| (counts[chunk.lot_id] += 1) <= 3 }.first(MAX_CHUNKS)
    rescue Embeddings::OllamaClient::Unavailable
      []
    end

    def lexical_chunks(query)
      lexical = Search::LexicalSearch.new(query)
      return [] unless lexical.searchable_terms?

      quoted = ApplicationRecord.connection.quote(query)
      lots = lexical.scope.limit(8).pluck(:id)
      return [] if lots.empty?

      LotChunk.includes(:lot).where(lot_id: lots)
        .where("to_tsvector('public.athenas_portuguese', text) @@ plainto_tsquery('public.athenas_portuguese', #{quoted})")
        .select("DISTINCT ON (lot_chunks.lot_id) lot_chunks.*")
        .order(:lot_id, :position).limit(MAX_CHUNKS).to_a
    end
  end
end
