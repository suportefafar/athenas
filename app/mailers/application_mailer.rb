class ApplicationMailer < ActionMailer::Base
  self.delivery_job = MailDeliveryJob
  layout "mailer"
end
