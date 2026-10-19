class Admin::LotsController < ApplicationController
  before_action :require_admin
  def index
    @page = [ params[:page].to_i, 1 ].max
    @total = Lot.count
    @lots = Lot.includes(:uploader).order(created_at: :desc, id: :desc).limit(20).offset((@page - 1) * 20)
  end
end
