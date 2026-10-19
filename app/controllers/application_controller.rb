class ApplicationController < ActionController::Base
  before_action :authenticate
  before_action :private_response
  helper_method :current_user

  private

  def current_user = Current.user

  def authenticate
    Current.session = Session.includes(:user).find_by(id: cookies.signed[:session_id], expires_at: Time.current..)
    redirect_to new_session_path unless current_user
  end

  def private_response
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "same-origin"
  end

  def require_admin
    head :forbidden unless current_user.admin?
  end
end
