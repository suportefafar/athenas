require "test_helper"
class AccessTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  setup do
    @user = create_user
    @other = create_user
    @lot = create_lot(uploader: @other, name: "Documento global.txt", extracted_text: "capacitação")
    @lot.file.attach(io: StringIO.new("conteudo original"), filename: @lot.name, content_type: "text/plain")
  end

  test "todas as rotas privadas exigem login" do
    [ root_path, search_path(q: "capacitação"), new_upload_path, my_uploads_path, lot_path(@lot), preview_lot_path(@lot), download_lot_path(@lot), admin_users_path, admin_lots_path ].each do |path|
      get path
      assert_redirected_to new_session_path
    end
    post uploads_path
    assert_redirected_to new_session_path
    delete lot_path(@lot)
    assert_redirected_to new_session_path
    assert Lot.exists?(@lot.id)
  end

  test "usuário pesquisa e baixa lote de outro autor mas não pode excluir" do
    login(@user)
    get search_path(q: "capacitação")
    assert_response :success
    assert_select "a", text: @lot.name
    assert_no_difference "LotAccess.count" do
      get download_lot_path(@lot)
      assert_response :success
      assert_equal "conteudo original", response.body
      assert_match "attachment", response.headers["Content-Disposition"]
    end
    assert_difference "LotAccess.count", 1 do
      get lot_path(@lot)
      assert_response :success
      assert_select "h1", text: @lot.name
      assert_select "button", text: "Excluir lote", count: 0
    end
    delete lot_path(@lot)
    assert_response :forbidden
    assert Lot.exists?(@lot.id)
  end

  test "rotas Active Storage públicas e cadastro público inexistem" do
    assert_not Rails.application.config.active_storage.draw_routes
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/rails/active_storage/blobs/redirect/token/file.txt") }
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/users/new") }
  end

  test "apenas admin cadastra usuários comuns com convite sem senha em email" do
    login(@user)
    post admin_users_path, params: { user: { name: "Pessoa", email_address: "new@example.test" } }
    assert_response :forbidden
    delete session_path
    admin = create_user(role: "admin")
    login(admin)
    assert_enqueued_emails 1 do
      post admin_users_path, params: { user: { name: "Convidado", email_address: "new@example.test", role: "admin", password: "senha-injetada" } }
    end
    user = User.find_by!(email_address: "new@example.test")
    assert_equal "user", user.role
    assert user.invited?
    token = user.invite!
    delete session_path
    get invitation_path(token)
    assert_response :success
    patch invitation_path(token), params: { password: "nova-senha-segura", password_confirmation: "nova-senha-segura" }
    assert_redirected_to new_session_path
    assert_not user.reload.invited?
    assert user.authenticate("nova-senha-segura")
    patch invitation_path(token), params: { password: "outra-senha-segura", password_confirmation: "outra-senha-segura" }
    assert_response :gone
  end

  test "lista uploads em todos os estados e mostra aviso global" do
    login(@user)
    Lot::STATUSES.each { |status| create_lot(uploader: @user, status: status) }
    get my_uploads_path
    assert_response :success
    Lot::STATUS_LABELS.each_value { |label| assert_includes response.body, label }
    get new_upload_path
    assert_includes response.body, "Os arquivos enviados poderão ser consultados por todos os usuários do Athenas"
  end

  test "preview seguro e HTML SVG nunca inline" do
    login(@user)
    @lot.update!(content_type: "image/svg+xml")
    get preview_lot_path(@lot)
    assert_response :unprocessable_entity
    @lot.update!(content_type: "application/pdf")
    get preview_lot_path(@lot)
    assert_response :success
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_match "inline", response.headers["Content-Disposition"]
    assert_match "sandbox", response.headers["Content-Security-Policy"]
    assert_match "no-store", response.headers["Cache-Control"]
  end

  test "upload retorna imediatamente com job e nome escapado" do
    login(@user)
    upload = Rack::Test::UploadedFile.new(StringIO.new("conteúdo"), "text/plain", original_filename: "<script>.txt")
    assert_enqueued_with(job: ProcessLotJob) do
      post uploads_path, params: { files: [ upload ] }
    end
    assert_redirected_to my_uploads_path
    follow_redirect!
    assert_includes response.body, "processado em segundo plano"
    assert_includes response.body, "&lt;script&gt;.txt"
    assert_not_includes response.body, "<script>.txt"
  end

  test "home e páginas administrativas renderizam" do
    login(create_user(role: "admin"))
    [ root_path, admin_users_path, admin_lots_path ].each do |path|
      get path
      assert_response :success
    end
  end
  test "autor e admin excluem por HTTP e preservam auditoria" do
    login(@other)
    delete lot_path(@lot)
    assert_redirected_to my_uploads_path
    assert_not Lot.exists?(@lot.id)
    assert AuditEvent.exists?(subject_id: @lot.id, actor_id: @other.id)
    delete session_path
    admin = create_user(role: "admin")
    login(admin)
    another = create_lot(uploader: @user)
    delete lot_path(another)
    assert_redirected_to my_uploads_path
    assert_not Lot.exists?(another.id)
  end
end
