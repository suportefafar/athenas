require "test_helper"

class WorkflowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "login upload processamento email pesquisa detalhes download exclusão" do
    user = create_user
    login(user)
    stub_request(:post, "http://localhost:11434/api/embed").to_return(body: { embeddings: [ vector ] }.to_json)
    upload = Rack::Test::UploadedFile.new(StringIO.new("Afastamento para capacitação profissional"), "text/plain", original_filename: "requerimento.txt")
    assert_emails 1 do
      perform_enqueued_jobs(only: [ ProcessLotJob, MailDeliveryJob ]) do
        post uploads_path, params: { files: [ upload ] }
      end
    end
    assert_redirected_to my_uploads_path
    lot = user.lots.last
    assert_equal "ready", lot.status
    assert_equal 1, lot.lot_chunks.count
    get search_path(q: "afastamento capacitação")
    assert_response :success
    assert_select "a", text: "requerimento.txt"
    get lot_path(lot)
    assert_response :success
    assert_equal 1, lot.lot_accesses.count
    get download_lot_path(lot)
    assert_equal "Afastamento para capacitação profissional".b, response.body.b
    blob = lot.file.blob
    perform_enqueued_jobs(only: PurgeBlobJob) { delete lot_path(lot) }
    assert_redirected_to my_uploads_path
    assert_not Lot.exists?(lot.id)
    assert_not blob.service.exist?(blob.key)
    assert AuditEvent.exists?(subject_id: lot.id, action: "lot.deleted")
  end
end
