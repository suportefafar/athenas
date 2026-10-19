class InvitationMailer < ApplicationMailer
  self.log_arguments = false if respond_to?(:log_arguments=)
  def invite(user, token)
    @user = user
    @url = invitation_url(token)
    mail(to: user.email_address, subject: "Athenas — defina sua senha")
  end
end
