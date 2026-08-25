require "test_helper"

# The portal-side CRUD for releases. The upload itself is a presigned PUT from the browser
# straight to R2, so what is testable here is everything around it: the two API calls the
# page makes, and the edit/delete rules.
class AdminReleasesTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "boss@stampezi.it", password: "secret-one")
    post "/admin/login", params: { email: @user.email, password: "secret-one" }
    follow_redirect!

    @shop = Shop.create_with_license!(name: "Test Shop", months: 1)
    @sha = "b" * 64
    @deleted = []
  end

  # R2's two network calls, swapped for local ones. Minitest 6 dropped Object#stub and
  # replacing the singleton method is all it ever did.
  def without_r2
    singleton = R2.singleton_class
    original_size = singleton.instance_method(:object_size)
    original_delete = singleton.instance_method(:delete_object)
    deleted = @deleted

    singleton.define_method(:object_size) { |_key| 240_000_000 }
    singleton.define_method(:delete_object) { |key| deleted << key }
    yield
  ensure
    singleton.define_method(:object_size, original_size)
    singleton.define_method(:delete_object, original_delete)
  end

  # Exactly what the upload page does: reserve, (PUT to R2), confirm.
  def upload!(version)
    post "/api/agent-releases", params: { version:, sha256: @sha }, as: :json
    assert_response :success
    id = response.parsed_body["id"]

    without_r2 { post "/api/agent-releases/#{id}/publish", as: :json }
    assert_response :success
    AgentRelease.find(id)
  end

  test "the upload page is behind the admin login" do
    reset!
    get "/admin/agent_releases/upload"
    assert_redirected_to "/admin/login?next=%2Fadmin%2Fagent_releases%2Fupload"
  end

  test "the upload page renders the three fields it posts" do
    get "/admin/agent_releases/upload"
    assert_response :success
    assert_select "input#version"
    assert_select "textarea#notes"
    assert_select "input#file"
  end

  test "a signed-in admin can reserve and publish without a bearer token" do
    release = upload!("1.0.0")

    assert release.installable?
    assert_equal 240_000_000, release.size_bytes
    assert_equal "agent/1.0.0/StampeziSetup.exe", release.object_key
  end

  test "the index and show pages list what exists" do
    upload!("1.0.0")

    get "/admin/agent_releases"
    assert_response :success
    assert_match "1.0.0", response.body

    get "/admin/agent_releases/#{AgentRelease.find_by(version: '1.0.0').id}"
    assert_response :success
    assert_match @sha, response.body
  end

  test "only the notes can be edited" do
    release = upload!("1.0.0")

    patch "/admin/agent_releases/#{release.id}", params: {
      agent_release: { notes: "Adds automatic updates", version: "9.9.9", sha256: "c" * 64 }
    }

    release.reload
    assert_equal "Adds automatic updates", release.notes
    # Those describe bytes already sitting in R2; letting the row drift from them would
    # make it lie about what a shop is about to download.
    assert_equal "1.0.0", release.version
    assert_equal @sha, release.sha256
  end

  test "deleting a release takes its installer out of R2 with it" do
    release = upload!("1.0.0")

    without_r2 { delete "/admin/agent_releases/#{release.id}" }

    assert_equal [ "agent/1.0.0/StampeziSetup.exe" ], @deleted
    assert_nil AgentRelease.find_by(version: "1.0.0")
  end

  test "a release a shop is targeted at cannot be deleted" do
    release = upload!("1.0.0")
    @shop.update!(target_agent_version: "1.0.0")

    without_r2 { delete "/admin/agent_releases/#{release.id}" }

    assert_empty @deleted, "the shop would be left asking for a build nobody can serve"
    assert AgentRelease.find_by(version: "1.0.0").installable?
    assert_match(/still targeted/, flash[:alert])
  end

  test "deleting an already-pruned release does not go back to R2 for it" do
    release = upload!("1.0.0")
    release.update!(pruned_at: Time.current)

    without_r2 { delete "/admin/agent_releases/#{release.id}" }

    assert_empty @deleted
    assert_nil AgentRelease.find_by(version: "1.0.0")
  end

  test "shops can be pointed at a version in bulk, and frozen again" do
    upload!("1.0.1")
    other = Shop.create_with_license!(name: "Other Shop", months: 1)

    post "/admin/shops/batch_action", params: {
      batch_action: "set_target_version",
      collection_selection: [ @shop.id, other.id ],
      batch_action_inputs: { version: "1.0.1" }.to_json
    }

    assert_equal "1.0.1", @shop.reload.target_agent_version
    assert_equal "1.0.1", other.reload.target_agent_version

    post "/admin/shops/batch_action", params: {
      batch_action: "set_target_version",
      collection_selection: [ @shop.id ],
      batch_action_inputs: { version: "" }.to_json
    }

    assert_nil @shop.reload.target_agent_version, "an empty version freezes the shop"
    assert_equal "1.0.1", other.reload.target_agent_version
  end
end
