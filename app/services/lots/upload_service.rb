module Lots
  class UploadService
    MAX_BYTES = 10 * 1024 * 1024
    class InvalidUpload < StandardError; end

    def call(upload, uploader:)
      raise InvalidUpload, "Arquivo inválido." unless upload.respond_to?(:tempfile)
      size = upload.tempfile.size
      max = [ ENV.fetch("MAX_UPLOAD_BYTES", MAX_BYTES).to_i, MAX_BYTES ].min
      raise InvalidUpload, "Arquivo maior que 10 MB: envio recusado." if size > max
      raise InvalidUpload, "Arquivo vazio: envio recusado." if size.zero?
      name = upload.original_filename.to_s.encode("UTF-8", invalid: :replace, undef: :replace).tr("\\", "/").split("/").last.to_s.gsub(/[[:cntrl:]]/, "").strip.first(255)
      name = "Arquivo" if name.blank?
      mime = Marcel::MimeType.for(upload.tempfile, name: name)
      upload.tempfile.rewind
      lot = nil
      blob = nil
      Lot.transaction do
        lot = Lot.create!(uploader: uploader, name: name, byte_size: size, content_type: mime)
        # Store the original before the queue record becomes visible at commit.
        blob = ActiveStorage::Blob.create_and_upload!(io: upload.tempfile, filename: name, content_type: mime, identify: false)
        lot.file.attach(blob)
        lot.update!(checksum: blob.checksum)
        ProcessLotJob.perform_later(lot.id)
      end
      lot
    rescue StandardError
      if blob && !ActiveStorage::Attachment.exists?(blob_id: blob.id)
        blob.purge
        blob.service.delete(blob.key)
      end
      raise
    end
  end
end
