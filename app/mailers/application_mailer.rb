class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("SMTP_FROM", "no-reply@example.local") }
  self.delivery_job = MailDeliveryJob
  layout "mailer"
end
