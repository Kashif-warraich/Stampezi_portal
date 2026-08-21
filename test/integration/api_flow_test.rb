require "test_helper"

class ApiFlowTest < ActionDispatch::IntegrationTest
  setup do
    @shop = Shop.create_with_license!(name: "Test Shop", months: 1)
    @license = @shop.license.license_number
    @admin = { "Authorization" => "Bearer #{ENV.fetch('ADMIN_TOKEN', 'test-token')}" }
  end

  test "admin API refuses callers with no session and no token" do
    get "/api/shops"
    assert_response :unauthorized
  end

  test "licence binds to the first machine and refuses the second" do
    post "/api/license/check", params: { license: @license, machineFingerprint: "A" }, as: :json
    assert_response :success
    assert_equal "valid", response.parsed_body["status"]

    post "/api/license/check", params: { license: @license, machineFingerprint: "B" }, as: :json
    assert_equal "machine-mismatch", response.parsed_body["status"]

    # The bound machine still checks in fine.
    post "/api/license/check", params: { license: @license, machineFingerprint: "A" }, as: :json
    assert_equal "valid", response.parsed_body["status"]
    assert_not_nil @shop.license.reload.last_check_at
  end

  test "timestamps serialise as ISO 8601 with milliseconds" do
    get "/api/shops", headers: @admin
    created = response.parsed_body["shops"].first["createdAt"]

    # The desktop service and the admin UI both parse this exact shape.
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z/, created)
  end

  test "a file can be claimed exactly once" do
    upload = UploadSession.create!(shop: @shop, status: "Uploaded", file_name: "a.pdf", object_key: "k")

    get "/api/pending-files", params: { license: @license }
    assert_equal [ upload.id ], response.parsed_body["files"].map { |f| f["id"] }

    post "/api/files/#{upload.id}/download-url", params: { license: @license }, as: :json
    assert_response :success

    post "/api/files/#{upload.id}/download-url", params: { license: @license }, as: :json
    assert_response :conflict
    assert_equal "already-delivered", response.parsed_body["error"]

    # Delivered rows never come back in the poll.
    get "/api/pending-files", params: { license: @license }
    assert_empty response.parsed_body["files"]
  end

  test "one shop cannot claim another shop's file, and cannot tell it exists" do
    other = Shop.create_with_license!(name: "Other", months: 1)
    upload = UploadSession.create!(shop: other, status: "Uploaded", file_name: "a.pdf", object_key: "k")

    post "/api/files/#{upload.id}/download-url", params: { license: @license }, as: :json
    assert_response :not_found
    assert_equal "Session not found", response.parsed_body["error"]
    assert_equal "Uploaded", upload.reload.status
  end

  test "the upload slot comes from the QR cookie, not the request body" do
    post "/api/upload-session", params: { fileName: "a.pdf" }, as: :json
    assert_response :unauthorized

    get "/upload", params: { l: @license }
    assert_redirected_to "/upload"

    post "/api/upload-session", params: { fileName: "a.exe" }, as: :json
    assert_response :bad_request
  end
end
