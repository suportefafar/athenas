Rails.application.config.filter_parameters += %i[password password_confirmation token invitation_token q query prompt content message extracted_text text embedding files email_address]
# SQL binds and Action Mailer bodies must never reach logs.
ActiveRecord::Base.logger = nil
ActionMailer::Base.logger = nil
ActiveJob::Base.logger = ActiveSupport::Logger.new(Rails.root.join("log/jobs.log"), 3, 1.megabyte)
