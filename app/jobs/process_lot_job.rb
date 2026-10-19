class ProcessLotJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  # The database connection owns a per-lot advisory lock while processing.
  # Deletion does not wait for extraction; publication locks and rechecks the row.
  def perform(lot_id)
    ApplicationRecord.connection_pool.with_connection do |connection|
      key = Integer(lot_id)
      locked = connection.select_value("SELECT pg_try_advisory_lock(18421, #{key})")
      return unless locked
      begin
        process(key)
      ensure
        connection.execute("SELECT pg_advisory_unlock(18421, #{key})")
      end
    end
  end

  private

  def process(id)
    publish(id)
    lot = Lot.find_by(id: id)
    notify(lot) if lot && %w[ready partial failed rejected].include?(lot.status)
  end

  def publish(id)
    lot = Lot.find_by(id: id)
    return unless lot
    return if %w[ready partial failed rejected].include?(lot.status)
    lot.update!(status: "processing")
    raise Lots::ExtractionService::Invalid, "Arquivo original indisponível." unless lot.file.attached?
    result = lot.file.open { |file| Lots::ExtractionService.new.call(file.path, name: lot.name) }
    chunks, warnings = Lots::IndexingService.new.prepare(result.text)
    warnings = (result.warnings + warnings).uniq
    Lot.transaction do
      lot = Lot.lock.find_by(id: id)
      return unless lot
      lot.lot_chunks.delete_all
      chunks.each { |chunk| lot.lot_chunks.create!(chunk) }
      metadata = result.metadata.merge("origem" => "upload", "enviado_por" => lot.uploader.name, "data_upload" => lot.created_at.to_date.to_s)
      lot.update!(status: warnings.any? ? "partial" : "ready", extracted_text: result.text,
        content_type: result.content_type, page_count: result.page_count, metadata: metadata,
        metadata_search_text: metadata.values.join(" "), processing_warnings: warnings,
        processing_error: nil, indexed_at: Time.current)
    end
  rescue Lots::ExtractionService::Rejected => error
    finish_error(id, "rejected", error.message)
  rescue Lots::ExtractionService::Invalid => error
    finish_error(id, "failed", error.message)
  rescue ActiveRecord::RecordNotFound, ActiveStorage::FileNotFoundError
    finish_error(id, "failed", "Arquivo original indisponível.")
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::ConnectionTimeoutError, ActiveRecord::Deadlocked
    raise
  rescue StandardError
    finish_error(id, "failed", "Não foi possível concluir o processamento com segurança.")
  end

  def finish_error(id, status, message)
    lot = nil
    Lot.transaction do
      lot = Lot.lock.find_by(id: id)
      return unless lot
      lot.lot_chunks.delete_all
      lot.update!(status: status, processing_error: message, extracted_text: nil, metadata_search_text: nil)
    end
  end

  def notify(lot)
    lot.with_lock do
      return if lot.notified_at
      LotProcessingMailer.completed(lot).deliver_later
      lot.update!(notified_at: Time.current)
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end
end
