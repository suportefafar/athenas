class Admin::UsersController < ApplicationController
  before_action :require_admin

  def index
    @users = User.order(:name)
    @user = User.new
  end

  def create
    @user = User.new(params.require(:user).permit(:name, :email_address))
    @user.password = SecureRandom.base64(32)
    @user.role = "user"
    User.transaction do
      if @user.save
        token = @user.invite!
        InvitationMailer.invite(@user, token).deliver_later
        redirect_to admin_users_path, notice: "Usuário criado. Convite para definir senha enviado por e-mail."
      else
        @users = User.order(:name)
        render :index, status: :unprocessable_entity
      end
    end
  end

  def invite
    user = User.find(params[:id])
    return head :forbidden if user.admin?
    user.with_lock do
      user.sessions.destroy_all
      InvitationMailer.invite(user, user.invite!).deliver_later
    end
    redirect_to admin_users_path, notice: "Novo convite enviado; o anterior foi invalidado."
  end
end
