ActiveSupport.on_load(:active_job) do
  ActiveJob::Base.log_arguments = false
end
