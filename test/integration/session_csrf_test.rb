require "test_helper"

class SessionCsrfTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @previous_protection = ActionController::Base.allow_forgery_protection
    @previous_origin_check = ActionController::Base.forgery_protection_origin_check
    ActionController::Base.allow_forgery_protection = true
    ActionController::Base.forgery_protection_origin_check = true
    get new_session_path
    @token = css_select('meta[name="csrf-token"]').first["content"]
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @previous_protection
    ActionController::Base.forgery_protection_origin_check = @previous_origin_check
  end

  test "login permite origem local com token e política compatível com navegador" do
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    post session_path, params: credentials.merge(authenticity_token: @token), headers: { "Origin" => request.base_url }
    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_equal "same-origin", response.headers["Referrer-Policy"]
  end

  test "login rejeita requisição sem token CSRF" do
    assert_no_difference "Session.count" do
      post session_path, params: credentials, headers: { "Origin" => request.base_url }
      assert_response 422
    end
  end

  test "login rejeita outra origem mesmo com token CSRF válido" do
    assert_no_difference "Session.count" do
      post session_path, params: credentials.merge(authenticity_token: @token), headers: { "Origin" => "https://external.example" }
      assert_response 422
    end
  end

  private

  def credentials
    { email_address: @user.email_address, password: "senha-segura-de-teste" }
  end
end
