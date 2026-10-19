module Search
  Result = Struct.new(:lots, :total, :page, :mode, :warning, keyword_init: true) do
    def pages = (total.to_f / 20).ceil
  end
end
