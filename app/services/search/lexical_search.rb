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
      # PostgreSQL treats Bitcoin.pdf as a hostname token. Also search a filename
      # with separators expanded so a bare title can find an exact file match.
      filename = "to_tsvector('public.athenas_portuguese', regexp_replace(name, '[._/\\-]+', ' ', 'g'))"
      Lot.searchable.where("search_vector @@ #{tsquery} OR #{filename} @@ #{tsquery}")
        .order(Arel.sql("ts_rank(search_vector, #{tsquery}) DESC, lots.created_at DESC, lots.id DESC"))
    end
  end
end
