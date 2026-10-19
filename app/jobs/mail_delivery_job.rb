class MailDeliveryJob < ActionMailer::MailDeliveryJob
  self.log_arguments = false
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
end
