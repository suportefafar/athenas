require "test_helper"
class DeletionAndPopularityTest < ActiveSupport::TestCase
  setup { @user = create_user }

  test "exclusão limpa busca popularidade arquivo e mantém duplicado e auditoria" do
    lot = Lots::UploadService.new.call(uploaded_file, uploader: @user)
    duplicate = Lots::UploadService.new.call(uploaded_file, uploader: create_user)
    lot.update!(status: "ready", extracted_text: "capacitação")
    add_chunk(lot)
    lot.lot_accesses.create!(user: @user, accessed_at: Time.current)
    blob = lot.file.blob
    perform_enqueued_jobs(only: PurgeBlobJob) { Lots::DeletionService.new.call(lot, actor: @user) }
    assert_not Lot.exists?(lot.id)
    assert_not LotChunk.exists?(lot_id: lot.id)
    assert_not LotAccess.exists?(lot_id: lot.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not blob.service.exist?(blob.key)
    assert Lot.exists?(duplicate.id)
    assert duplicate.file.attached?
    audit = AuditEvent.find_by!(subject_id: lot.id)
    assert_equal "lot.deleted", audit.action
    assert_equal @user.id, audit.actor_id
    assert_equal lot.name, audit.subject_snapshot["name"]
    assert_not_includes audit.subject_snapshot.to_json, "capacitação"
  end

  test "admin pode excluir lote de qualquer autor" do
    lot = create_lot
    admin = create_user(role: "admin")
    Lots::DeletionService.new.call(lot, actor: admin)
    assert_not Lot.exists?(lot.id)
  end

  test "ranking considera apenas 30 dias e desempata por último acesso" do
    older = create_lot
    recent = create_lot
    outdated = create_lot
    hidden = create_lot(status: "processing")
    2.times { older.lot_accesses.create!(user: @user, accessed_at: 2.days.ago) }
    2.times { recent.lot_accesses.create!(user: @user, accessed_at: 1.day.ago) }
    4.times { outdated.lot_accesses.create!(user: @user, accessed_at: 31.days.ago) }
    hidden.lot_accesses.create!(user: @user, accessed_at: Time.current)
    assert_equal [ recent.id, older.id ], Lot.popular.map(&:id)
  end
end
