require Rails.root.join("app/mailers/hermes_delivery_method")

ActionMailer::Base.add_delivery_method :hermes, HermesDeliveryMethod
if Rails.env.production?
  Rails.application.config.action_mailer.delivery_method = :hermes
  ActionMailer::Base.delivery_method = :hermes
end
