class My::UploadsController < ApplicationController
  def index
    @page = [ params[:page].to_i, 1 ].max
    @total = current_user.lots.count
    @lots = current_user.lots.order(created_at: :desc, id: :desc).limit(20).offset((@page - 1) * 20)
  end
end
