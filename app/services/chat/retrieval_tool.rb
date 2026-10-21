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

      lexical = lexical_chunks(query, lot_id: lot_id)
      semantic = semantic_chunks(query, lot_id: lot_id)
      # Reciprocal-rank fusion combines exact and semantic matches even when
      # embeddings are incomplete. Neighbouring chunks preserve table context.
      scores = Hash.new(0.0)
      [ lexical, semantic ].each { |list| list.each_with_index { |chunk, index| scores[chunk.id] += 1.0 / (60 + index + 1) } }
      ranked = (lexical + semantic).uniq(&:id).sort_by { |chunk| -scores[chunk.id] }.first(MAX_CHUNKS)
      chunks = with_neighbors(ranked)
      mode = lexical.any? && semantic.any? ? "hybrid" : (lexical.any? ? "lexical" : "semantic")
      {
        mode: mode,
        query: query,
        documents: chunks.each_with_index.map do |chunk, index|
          {
            reference: index + 1,
            lot_id: chunk.lot_id,
            title: chunk.lot.name,
            position: chunk.position + 1,
            coverage: "excerpts",
            excerpt: chunk.text
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
          coverage: positions.size == chunks.size ? "full_chunks" : "excerpts",
          excerpts: positions.map { |index| { position: chunks[index].position + 1, text: chunks[index].text } }
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
      candidates.first(MAX_CHUNKS)
    rescue Embeddings::OllamaClient::Unavailable
      []
    end

    def lexical_chunks(query, lot_id: nil)
      lexical = Search::LexicalSearch.new(query)
      return [] unless lexical.searchable_terms?

      quoted = ApplicationRecord.connection.quote(query)
      lots = lot_id ? Lot.searchable.where(id: lot_id).pluck(:id) : lexical.scope.limit(24).pluck(:id)
      return [] if lots.empty?

      LotChunk.includes(:lot).where(lot_id: lots)
        .where("to_tsvector('public.athenas_portuguese', text) @@ plainto_tsquery('public.athenas_portuguese', #{quoted})")
        .order(Arel.sql("ts_rank(to_tsvector('public.athenas_portuguese', text), plainto_tsquery('public.athenas_portuguese', #{quoted})) DESC"))
        .order(:lot_id, :position).limit(MAX_CHUNKS).to_a
    end

    def with_neighbors(chunks)
      return [] if chunks.empty?

      ids = chunks.group_by(&:lot_id).flat_map do |id, matches|
        positions = matches.flat_map { |chunk| [ chunk.position - 1, chunk.position, chunk.position + 1 ] }.select { |position| position >= 0 }.uniq
        LotChunk.where(lot_id: id, position: positions).pluck(:id)
      end
      # A fixed context budget, without truncating individual evidence spans.
      neighbors = LotChunk.includes(:lot).where(id: ids).order(:lot_id, :position).to_a
      selected = chunks.dup
      neighbors.each { |chunk| selected << chunk unless selected.any? { |item| item.id == chunk.id } }
      selected.first(20).sort_by { |chunk| [ chunk.lot_id, chunk.position ] }
    end
  end
end
