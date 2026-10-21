module Chat
  class FileSearchTool
    MAX_RESULTS = 24

    def call(query)
      result = Search::Service.new.call(query)
      lots = result.lots.first(MAX_RESULTS)
      if result.total > lots.size && lots.size < MAX_RESULTS
        lots.concat(Search::Service.new.call(query, page: 2).lots.first(MAX_RESULTS - lots.size))
      end
      snippets = matching_chunks(lots, query)
      {
        mode: result.mode.to_s,
        total: result.total,
        warning: [ result.warning, ("A pesquisa encontrou #{result.total} documentos; foram selecionados #{lots.size}. Refine a consulta para examinar os demais." if result.total > lots.size) ].compact.join(" ").presence,
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

    def catalog
      scope = Lot.searchable.order(:id)
      total = scope.count
      { mode: "catalog", query: "", total: total,
        warning: ("O acervo contém #{total} documentos; foram selecionados #{MAX_RESULTS}. Refine a consulta para examinar os demais." if total > MAX_RESULTS),
        documents: scope.limit(MAX_RESULTS).map { |lot| { lot_id: lot.id, title: lot.name, pages: lot.page_count } } }
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
