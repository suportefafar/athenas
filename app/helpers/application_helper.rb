module ApplicationHelper
  def lot_status_class(status)
    case status
    when "ready" then "ffds-badge-subtle-success"
    when "partial" then "ffds-badge-warning"
    when "failed", "rejected" then "ffds-badge-danger"
    when "processing" then "ffds-badge-info"
    else "ffds-badge-light"
    end
  end
end
