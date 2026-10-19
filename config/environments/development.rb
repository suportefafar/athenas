Rails.application.configure do
  config.enable_reloading = true
  config.hosts << URI.parse(ENV.fetch("APP_BASE_URL", "http://localhost:3000")).host
  config.eager_load = false
  config.consider_all_requests_local = true
  config.active_storage.service = :local
  config.cache_store = :memory_store
  config.action_mailer.delivery_method = :file
  config.action_mailer.file_settings = { location: Rails.root.join("tmp/mail") }
  config.action_mailer.raise_delivery_errors = true
end
