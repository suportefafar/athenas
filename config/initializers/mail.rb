base = URI.parse(ENV.fetch("APP_BASE_URL", "http://localhost:3000"))
raise "APP_BASE_URL deve ser uma URL HTTP(S) com host." unless %w[http https].include?(base.scheme) && base.host.present?
options = { host: base.host, port: base.port, protocol: base.scheme }
Rails.application.config.action_mailer.default_url_options = options
# Logging configuration may already have loaded Action Mailer. Apply operational
# settings to the class too, independently of lazy-loading order.
ActionMailer::Base.default_url_options = options
