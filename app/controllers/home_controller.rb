class HomeController < ApplicationController
  def index
    @lots = Lot.popular
  end
end
