class AuditEvent < ApplicationRecord
  belongs_to :actor, class_name: "User"
end
