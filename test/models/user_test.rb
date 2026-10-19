require "test_helper"
class UserTest < ActiveSupport::TestCase
  test "normaliza email e exige senha forte" do
    user = create_user(email_address: "  PERSON@EXAMPLE.TEST ")
    assert_equal "person@example.test", user.email_address
    assert_not user.update(password: "curta")
  end

  test "banco permite um administrador e impede rebaixamento e exclusão" do
    admin = create_user(role: "admin")
    assert_not admin.update(role: "user")
    admin.reload
    assert_not admin.destroy
    User.transaction(requires_new: true) do
      assert_raises(ActiveRecord::RecordNotUnique) { create_user(role: "admin") }
      raise ActiveRecord::Rollback
    end
  end

  test "seed idempotente não altera credenciais" do
    previous = ENV.to_h.slice("ADMIN_EMAIL", "ADMIN_PASSWORD")
    ENV["ADMIN_EMAIL"] = "admin-seed@example.test"
    ENV["ADMIN_PASSWORD"] = "senha-inicial-segura"
    load Rails.root.join("db/seeds.rb")
    admin = User.find_by!(role: "admin")
    digest = admin.password_digest
    ENV["ADMIN_PASSWORD"] = "outra-senha-de-instalacao"
    load Rails.root.join("db/seeds.rb")
    assert_equal 1, User.where(role: "admin").count
    assert_equal digest, admin.reload.password_digest
  ensure
    %w[ADMIN_EMAIL ADMIN_PASSWORD].each { |key| previous.key?(key) ? ENV[key] = previous[key] : ENV.delete(key) }
  end

  test "seed sem credenciais falha de modo claro" do
    previous = ENV.delete("ADMIN_PASSWORD")
    assert_raises(SystemExit) { capture_io { load Rails.root.join("db/seeds.rb") } }
  ensure
    ENV["ADMIN_PASSWORD"] = previous if previous
  end

  test "convite expira e não armazena token em claro" do
    user = create_user
    token = user.invite!
    assert_equal user, User.from_invitation(token)
    assert_not_equal token, user.invitation_digest
    user.update!(invitation_sent_at: 49.hours.ago)
    assert_nil User.from_invitation(token)
  end
end
