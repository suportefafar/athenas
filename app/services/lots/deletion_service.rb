module Lots
  class DeletionService
    def call(lot, actor:)
      raise ActiveRecord::RecordNotFound unless lot.deletable_by?(actor)
      blob = lot.file.blob if lot.file.attached?
      lot.with_lock do
        AuditEvent.create!(actor: actor, action: "lot.deleted", subject_type: "Lot", subject_id: lot.id,
          subject_snapshot: { name: lot.name, source_type: lot.source_type, uploader_id: lot.uploader_id }, created_at: Time.current)
        lot.file.detach
        lot.destroy!
        # Persist purge work in the same transaction, so a crash cannot orphan originals.
        PurgeBlobJob.perform_later(blob.id) if blob
      end
    end
  end
end
