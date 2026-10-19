CI.run do
  step "Style: Ruby", "bin/rubocop"
  step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "bin/rails test"
  step "Autoload", "bin/rails zeitwerk:check"
end
