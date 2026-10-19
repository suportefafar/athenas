class SessionsController < ApplicationController
  skip_before_action :authenticate, only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Muitas tentativas. Aguarde alguns minutos." }

  def new; end

  def create
    user = User.authenticate_by(email_address: params[:email_address], password: params[:password])
    if user && !user.invited?
      reset_session
      login = user.sessions.create!(expires_at: 2.weeks.from_now)
      cookies.signed[:session_id] = { value: login.id, httponly: true, same_site: :lax, secure: Rails.env.production?, expires: login.expires_at }
      redirect_to root_path
    else
      redirect_to new_session_path, alert: "E-mail ou senha inválidos."
    end
  end

  def destroy
    Current.session.destroy!
    cookies.delete(:session_id)
    reset_session
    redirect_to new_session_path, notice: "Você saiu do Athenas."
  end
end
