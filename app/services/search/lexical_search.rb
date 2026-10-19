module Search
  class LexicalSearch
    def initialize(query)
      @query = ApplicationRecord.connection.quote(query)
    end

    def searchable_terms?
      ApplicationRecord.connection.select_value("SELECT numnode(plainto_tsquery('public.athenas_portuguese', #{@query}))").to_i.positive?
    end

    def scope
      tsquery = "plainto_tsquery('public.athenas_portuguese', #{@query})"
      Lot.searchable.where("search_vector @@ #{tsquery}")
        .order(Arel.sql("ts_rank(search_vector, #{tsquery}) DESC, lots.created_at DESC, lots.id DESC"))
    end
  end
end
