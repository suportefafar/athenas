class SearchesController < ApplicationController
  def index
    @query = params[:q].to_s.strip
    if @query.length > 500
      @result = Search::Result.new(lots: [], total: 0, page: 1, mode: :lexical, warning: "Use uma consulta de até 500 caracteres.")
    else
      @result = Search::Service.new.call(@query, page: params[:page])
    end
  end
end
