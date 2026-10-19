class InvitationsController < ApplicationController
  skip_before_action :authenticate
  before_action :find_invitee
  rate_limit to: 10, within: 3.minutes, only: :update, with: -> { head :too_many_requests }

  def edit; end

  def update
    @user.with_lock do
      unless User.from_invitation(params[:token])
        head :gone
        return
      end
      if @user.update(password: params[:password], password_confirmation: params[:password_confirmation], invitation_digest: nil, invitation_sent_at: nil)
        @user.sessions.destroy_all
        redirect_to new_session_path, notice: "Senha definida. Entre com seu e-mail e senha."
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end

  private

  def find_invitee
    @user = User.from_invitation(params[:token])
    head :gone unless @user
  end
end
