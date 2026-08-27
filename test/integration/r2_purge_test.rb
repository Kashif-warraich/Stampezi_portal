require "test_helper"

# R2 holds files only until they reach a shop. These are the rules that decide when the
# bytes go, and the one that decides when they must not.
class R2PurgeTest < ActionDispatch::IntegrationTest
  setup do
    @shop = Shop.create_with_license!(name: "Test Shop", months: 1)
    @license = @shop.license.license_number
    @deleted = []
  end

  # Same idiom as the release tests: Minitest 6 dropped Object#stub, and replacing the
  # singleton method is all it ever did.
  def without_r2
    singleton = R2.singleton_class
    original = singleton.instance_method(:delete_objects)
    deleted = @deleted

    singleton.define_method(:delete_objects) { |keys| deleted.concat(keys) }
    yield
  ensure
    singleton.define_method(:delete_objects, original)
  end

  def stale!(upload)
    UploadSession.where(id: upload.id).update_all(updated_at: (UploadSession::PENDING_WINDOW + 1.minute).ago)
    upload
  end

  test "the poll deletes objects the shop can no longer be given" do
    upload = stale!(UploadSession.create!(
      shop: @shop, status: "Delivered", delivered_at: Time.current,
      file_name: "a.pdf", object_key: "shops/x/incoming/1/a.pdf"))

    without_r2 { get "/api/pending-files", params: { license: @license } }
    assert_response :success

    assert_equal [ "shops/x/incoming/1/a.pdf" ], @deleted
    assert_not_nil upload.reload.purged_at
  end

  test "a purged row is never offered to R2 twice" do
    stale!(UploadSession.create!(shop: @shop, status: "Delivered", delivered_at: Time.current,
                                 file_name: "a.pdf", object_key: "k"))

    without_r2 do
      get "/api/pending-files", params: { license: @license }
      get "/api/pending-files", params: { license: @license }
    end

    assert_equal [ "k" ], @deleted
  end

  test "a download still in flight keeps its object" do
    # Old enough to sweep, then claimed - which bumps updated_at. The desktop is pulling
    # these bytes right now; deleting them would lose the customer's job.
    upload = stale!(UploadSession.create!(shop: @shop, status: "Uploaded",
                                          file_name: "a.pdf", object_key: "k"))
    post "/api/files/#{upload.id}/download-url", params: { license: @license }, as: :json
    assert_response :success

    without_r2 { get "/api/pending-files", params: { license: @license } }

    assert_empty @deleted
    assert_nil upload.reload.purged_at
  end

  test "a file still waiting to be collected is left alone" do
    upload = UploadSession.create!(shop: @shop, status: "Uploaded", file_name: "a.pdf", object_key: "k")

    without_r2 { get "/api/pending-files", params: { license: @license } }

    assert_equal [ upload.id ], response.parsed_body["files"].map { |f| f["id"] }
    assert_empty @deleted
    assert_nil upload.reload.purged_at
  end

  test "an expired licence still has its files swept" do
    stale!(UploadSession.create!(shop: @shop, status: "Delivered", delivered_at: Time.current,
                                 file_name: "a.pdf", object_key: "k"))
    @shop.license.update!(expires_at: (License::GRACE_DAYS + 1).days.ago)

    without_r2 { get "/api/pending-files", params: { license: @license } }
    assert_response :forbidden

    # Not being allowed to collect files is no reason to keep paying to store them.
    assert_equal [ "k" ], @deleted
  end

  test "deleting a shop takes its objects with it" do
    UploadSession.create!(shop: @shop, status: "Uploaded", file_name: "a.pdf", object_key: "live")
    purged = UploadSession.create!(shop: @shop, status: "Delivered", file_name: "b.pdf", object_key: "gone")
    purged.update!(purged_at: Time.current)

    # The rows are the only record of these keys, so they have to go first.
    without_r2 { @shop.destroy! }

    assert_equal [ "live" ], @deleted
  end
end
