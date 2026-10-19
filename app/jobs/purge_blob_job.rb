class PurgeBlobJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(blob_id)
    blob = ActiveStorage::Blob.find_by(id: blob_id)
    return unless blob
    return if blob.attachments.exists?
    # Keep a durable reference until storage deletion succeeds, so retries can
    # clean the original even when the storage service is temporarily unavailable.
    blob.service.delete(blob.key)
    blob.purge
  end
end
