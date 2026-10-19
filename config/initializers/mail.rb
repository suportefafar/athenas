base = URI.parse(ENV.fetch("APP_BASE_URL", "http://localhost:3000"))
raise "APP_BASE_URL deve ser uma URL HTTP(S) com host." unless %w[http https].include?(base.scheme) && base.host.present?
options = { host: base.host, port: base.port, protocol: base.scheme }
Rails.application.config.action_mailer.default_url_options = options
# Logging configuration may already have loaded Action Mailer. Apply operational
# settings to the class too, independently of lazy-loading order.
ActionMailer::Base.default_url_options = options
if Rails.env.production?
  port = ENV.fetch("SMTP_PORT", 587).to_i
  smtp = {
    address: ENV.fetch("SMTP_ADDRESS"), port: port,
    user_name: ENV["SMTP_USERNAME"], password: ENV["SMTP_PASSWORD"],
    authentication: ENV["SMTP_USERNAME"].present? ? :plain : nil,
    open_timeout: 10, read_timeout: 10
  }
  if ENV.fetch("SMTP_SSL", "false").casecmp?("true") || port == 465
    smtp[:ssl] = true
  else
    smtp[:enable_starttls_auto] = true
  end
  Rails.application.config.action_mailer.delivery_method = :smtp
  Rails.application.config.action_mailer.smtp_settings = smtp
  ActionMailer::Base.delivery_method = :smtp
  ActionMailer::Base.smtp_settings = smtp
end
