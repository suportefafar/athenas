module Chat
  class RetrievalTool
    MAX_CHUNKS = 10
    MAX_OVERVIEW_EXCERPTS = 16

    def initialize(client: Embeddings::OllamaClient.new)
      @client = client
    end

    def call(query, lot_id: nil, overview: false)
      lot = Lot.searchable.find_by(id: lot_id) if lot_id
      return { mode: "document", query: query, documents: [] } if lot_id && !lot
      return document_overview(query, lot) if overview && lot

      chunks = semantic_chunks(query, lot_id: lot_id)
      mode = "semantic"
      if chunks.empty?
        chunks = lexical_chunks(query, lot_id: lot_id)
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

    def document_overview(query, lot)
      chunks = lot.lot_chunks.order(:position).to_a
      return { mode: "document", query: query, documents: [] } if chunks.empty?

      count = [ chunks.size, MAX_OVERVIEW_EXCERPTS ].min
      positions = if count == 1
        [ 0 ]
      else
        (0...count).map { |index| (index * (chunks.size - 1).fdiv(count - 1)).round }.uniq
      end
      {
        mode: "document",
        query: query,
        documents: [ {
          reference: 1, lot_id: lot.id, title: lot.name, pages: lot.page_count,
          sampled_chunks: positions.size, total_chunks: chunks.size,
          excerpts: positions.map { |index| { position: chunks[index].position + 1, text: chunks[index].text.first(1_000) } }
        } ]
      }
    end

    def semantic_chunks(query, lot_id: nil)
      vector = Embeddings::OllamaClient.sql_vector(@client.call(query))
      quoted = ApplicationRecord.connection.quote(vector)
      threshold = Float(ENV.fetch("CHAT_MIN_SIMILARITY", "0.48")).clamp(-1, 1)
      candidates = LotChunk.includes(:lot).joins(:lot)
        .where(lots: { status: %w[ready partial] }).where.not(embedding: nil)
      candidates = candidates.where(lot_id: lot_id) if lot_id
      candidates = candidates
        .where("1 - (lot_chunks.embedding <=> #{quoted}::vector) >= ?", threshold)
        .order(Arel.sql("lot_chunks.embedding <=> #{quoted}::vector"))
        .limit(40).to_a
      counts = Hash.new(0)
      candidates.select { |chunk| (counts[chunk.lot_id] += 1) <= 3 }.first(MAX_CHUNKS)
    rescue Embeddings::OllamaClient::Unavailable
      []
    end

    def lexical_chunks(query, lot_id: nil)
      lexical = Search::LexicalSearch.new(query)
      return [] unless lexical.searchable_terms?

      quoted = ApplicationRecord.connection.quote(query)
      lots = lot_id ? [ lot_id ] : lexical.scope.limit(8).pluck(:id)
      return [] if lots.empty?

      LotChunk.includes(:lot).where(lot_id: lots)
        .where("to_tsvector('public.athenas_portuguese', text) @@ plainto_tsquery('public.athenas_portuguese', #{quoted})")
        .select("DISTINCT ON (lot_chunks.lot_id) lot_chunks.*")
        .order(:lot_id, :position).limit(MAX_CHUNKS).to_a
    end
  end
end
