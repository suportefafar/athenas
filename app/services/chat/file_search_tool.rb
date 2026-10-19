module Chat
  class FileSearchTool
    MAX_RESULTS = 8

    def call(query)
      result = Search::Service.new.call(query)
      lots = result.lots.first(MAX_RESULTS)
      snippets = matching_chunks(lots, query)
      {
        mode: result.mode.to_s,
        total: result.total,
        warning: result.warning,
        query: query,
        documents: lots.each_with_index.map do |lot, index|
          {
            reference: index + 1,
            lot_id: lot.id,
            title: lot.name,
            pages: lot.page_count,
            uploaded_at: lot.created_at.to_date.to_s,
            excerpt: snippets[lot.id]&.text&.first(900)
          }
        end
      }
    end

    private

    def matching_chunks(lots, query)
      return {} if lots.empty?

      quoted = ApplicationRecord.connection.quote(query)
      LotChunk.where(lot_id: lots.map(&:id))
        .where("to_tsvector('public.athenas_portuguese', text) @@ plainto_tsquery('public.athenas_portuguese', #{quoted})")
        .select("DISTINCT ON (lot_chunks.lot_id) lot_chunks.*")
        .order(:lot_id, :position).to_a.index_by(&:lot_id)
    end
  end
end
