require "test_helper"
class ProcessLotJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  setup do
    @user = create_user
    @lot = Lots::UploadService.new.call(uploaded_file, uploader: @user)
    clear_enqueued_jobs
    stub_request(:post, "http://localhost:11434/api/embed").to_return(body: { embeddings: [ vector ] }.to_json)
  end

  test "pipeline publica ao terminar e job repetido não duplica chunks ou e-mails" do
    extractor = Object.new
    lot = @lot
    extraction = fake_extraction
    extractor.define_singleton_method(:call) do |*args, **options|
      raise "Publicou cedo" unless lot.reload.status == "processing" && !Lot.searchable.exists?(lot.id)
      extraction
    end
    Lots::ExtractionService.stub(:new, -> { extractor }) { ProcessLotJob.perform_now(@lot.id) }
    assert_equal "ready", @lot.reload.status
    assert_equal 1, @lot.lot_chunks.count
    assert_enqueued_emails 1
    ProcessLotJob.perform_now(@lot.id)
    assert_equal 1, @lot.lot_chunks.count
    assert_enqueued_emails 1
    assert_equal [ @lot.id ], Search::Service.new.call("capacitação").lots.map(&:id)
  end

  test "OCR parcial preserva texto mas só publica ao finalizar" do
    extractor = Object.new
    result = fake_extraction(warnings: [ "Página 80: OCR incompleto." ])
    extractor.define_singleton_method(:call) { |*args, **kwargs| result }
    Lots::ExtractionService.stub(:new, -> { extractor }) { ProcessLotJob.perform_now(@lot.id) }
    assert_equal "partial", @lot.reload.status
    assert_match "Página 80", @lot.processing_warnings.first
    assert_equal 1, Search::Service.new.call("capacitação").total
    assert_enqueued_emails 1
  end

  test "embeddings indisponíveis preservam busca lexical como partial" do
    stub_request(:post, "http://localhost:11434/api/embed").to_timeout
    ProcessLotJob.perform_now(@lot.id)
    assert_equal "partial", @lot.reload.status
    assert_equal 1, Search::Service.new.call("capacitação").total
    assert_nil @lot.lot_chunks.first.embedding
    assert_enqueued_emails 1
  end

  test "arquivo sem suporte indexa apenas metadados com aviso" do
    other = Lots::UploadService.new.call(uploaded_file("PK arquivo desconhecido", name: "arquivo.bin"), uploader: @user)
    ProcessLotJob.perform_now(other.id)
    assert_equal "partial", other.reload.status
    assert_empty other.extracted_text
    assert_match "Conteúdo não extraído", other.processing_warnings.first
  end

  test "rejeição e falha notificam sem publicar" do
    [ Lots::ExtractionService::Rejected, Lots::ExtractionService::Invalid ].each do |error|
      @lot.update!(status: "pending", notified_at: nil)
      extractor = Object.new
      extractor.define_singleton_method(:call) { |*args, **kwargs| raise error, "Documento recusado." }
      Lots::ExtractionService.stub(:new, -> { extractor }) { ProcessLotJob.perform_now(@lot.id) }
      assert_equal(error == Lots::ExtractionService::Rejected ? "rejected" : "failed", @lot.reload.status)
      assert_not Lot.searchable.exists?(@lot.id)
      assert_empty @lot.lot_chunks
    end
    assert_enqueued_emails 2
  end

  test "exclusão durante extração não recria índices nem publica" do
    extractor = Object.new
    lot, user, result = @lot, @user, fake_extraction
    extractor.define_singleton_method(:call) do |*args, **kwargs|
      Lots::DeletionService.new.call(lot, actor: user)
      result
    end
    Lots::ExtractionService.stub(:new, -> { extractor }) { ProcessLotJob.perform_now(@lot.id) }
    assert_not Lot.exists?(@lot.id)
    assert_equal 0, LotChunk.where(lot_id: @lot.id).count
    ProcessLotJob.perform_now(@lot.id)
    assert_not Lot.exists?(@lot.id)
    assert_enqueued_emails 0
  end

  test "e-mail operacional não inclui conteúdo extraído" do
    @lot.update!(status: "partial", extracted_text: "SEGREDO DO DOCUMENTO", processing_warnings: [ "OCR incompleto" ])
    mail = LotProcessingMailer.completed(@lot)
    assert_match @lot.name, mail.body.encoded
    assert_match "OCR incompleto", mail.body.encoded
    assert_not_includes mail.body.encoded, "SEGREDO DO DOCUMENTO"
    assert_includes mail.body.encoded, "#{ENV.fetch('APP_BASE_URL', 'http://localhost:3000')}/lots/#{@lot.id}"
  end
  test "falha ao enfileirar notificação não destrói indexação concluída" do
    job = ProcessLotJob.new
    job.stub(:notify, ->(*) { raise ActiveJob::EnqueueError, "fila indisponível" }) do
      assert_raises(ActiveJob::EnqueueError) { job.send(:process, @lot.id) }
    end
    assert_equal "ready", @lot.reload.status
    assert_equal 1, @lot.lot_chunks.count
    assert_nil @lot.notified_at
    ProcessLotJob.perform_now(@lot.id)
    assert_enqueued_emails 1
    assert @lot.reload.notified_at
  end
end
