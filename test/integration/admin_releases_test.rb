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
    @moved = []
  end

  # R2's two network calls, swapped for local ones. Minitest 6 dropped Object#stub and
  # replacing the singleton method is all it ever did.
  def without_r2
    singleton = R2.singleton_class
    original_size = singleton.instance_method(:object_size)
    original_delete = singleton.instance_method(:delete_object)
    deleted = @deleted

    original_move = singleton.instance_method(:move_object)
    moved = @moved

    singleton.define_method(:object_size) { |_key| 240_000_000 }
    singleton.define_method(:delete_object) { |key| deleted << key }
    singleton.define_method(:move_object) { |from, to| moved << [ from, to ] }
    yield
  ensure
    singleton.define_method(:object_size, original_size)
    singleton.define_method(:delete_object, original_delete)
    singleton.define_method(:move_object, original_move)
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

  test "the digest and object key are not editable" do
    release = upload!("1.0.0")

    patch "/admin/agent_releases/#{release.id}", params: {
      agent_release: { notes: "Adds automatic updates", sha256: "c" * 64, object_key: "agent/evil.exe" }
    }

    release.reload
    assert_equal "Adds automatic updates", release.notes
    # They describe bytes already sitting in R2. Only the version may be corrected, and
    # that moves the object with it.
    assert_equal @sha, release.sha256
    assert_equal "agent/1.0.0/StampeziSetup.exe", release.object_key
  end

  test "the delete control is a form, not a link needing JavaScript" do
    release = upload!("1.0.0")
    get "/admin/agent_releases/#{release.id}"

    # A <a data-method="delete"> would need jQuery-UJS, which this app does not load; it
    # would perform a GET and look like it had done nothing. button_to renders a real form.
    assert_select "form[action=?][method=post]", "/admin/agent_releases/#{release.id}" do
      assert_select "input[name=_method][value=delete]", 1
    end
    assert_select "a[data-method=delete][href=?]", "/admin/agent_releases/#{release.id}", 0
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

  test "renaming a release moves its installer with it" do
    release = upload!("1.0.0")

    without_r2 do
      patch "/admin/agent_releases/#{release.id}", params: {
        agent_release: { version: "1.0.1", notes: "typo in the version" }
      }
    end

    release.reload
    assert_equal "1.0.1", release.version
    # Otherwise the row and the bytes stop describing each other.
    assert_equal "agent/1.0.1/StampeziSetup.exe", release.object_key
    assert_equal [ [ "agent/1.0.0/StampeziSetup.exe", "agent/1.0.1/StampeziSetup.exe" ] ], @moved
  end

  test "a release a shop is targeted at cannot be renamed" do
    release = upload!("1.0.0")
    @shop.update!(target_agent_version: "1.0.0")

    without_r2 do
      patch "/admin/agent_releases/#{release.id}", params: { agent_release: { version: "1.0.1" } }
    end

    assert_equal "1.0.0", release.reload.version
    assert_empty @moved
    assert_match(/targeted at 1\.0\.0/, flash[:alert])
  end

  test "renaming onto a version that already exists is refused" do
    upload!("1.0.0")
    release = upload!("1.0.1")

    without_r2 do
      patch "/admin/agent_releases/#{release.id}", params: { agent_release: { version: "1.0.0" } }
    end

    assert_equal "1.0.1", release.reload.version
    assert_empty @moved
  end

  test "the roll-out form points shops at a version, and freezes the ones removed from it" do
    release = upload!("1.0.1")
    other = Shop.create_with_license!(name: "Other Shop", months: 1)

    get "/admin/agent_releases/#{release.id}"
    assert_select "form[action=?]", "/admin/agent_releases/#{release.id}/roll_out"
    assert_select "input[type=checkbox][name=?]", "shop_ids[]", 2

    post "/admin/agent_releases/#{release.id}/roll_out", params: { shop_ids: [ @shop.id, other.id ] }
    assert_equal "1.0.1", @shop.reload.target_agent_version
    assert_equal "1.0.1", other.reload.target_agent_version

    # Dropping a shop freezes it where it is rather than rolling it back - that has to be
    # an explicit choice.
    post "/admin/agent_releases/#{release.id}/roll_out", params: { shop_ids: [ other.id ] }
    assert_nil @shop.reload.target_agent_version
    assert_equal "1.0.1", other.reload.target_agent_version
  end

  # Two different questions, so two columns. Targeted is intent and only an operator moves
  # it; Running is what the shops report, and it moves on its own.
  test "the releases list counts what is targeted and what is actually running" do
    release = upload!("1.0.1")

    get "/admin/agent_releases"
    assert_select "tbody tr td:nth-child(2)", text: "0"   # running
    assert_select "tbody tr td:nth-child(3)", text: "0"   # targeted

    # Rolling out moves Targeted immediately. Running does not: the shop is still on its
    # old build until it checks in and says otherwise.
    post "/admin/agent_releases/#{release.id}/roll_out", params: { shop_ids: [ @shop.id ] }

    get "/admin/agent_releases"
    assert_select "tbody tr td:nth-child(2)", text: "0"
    assert_select "tbody tr td:nth-child(3)", text: "1"
  end

  test "the running count follows the licence check with no operator action" do
    release = upload!("1.0.1")
    post "/admin/agent_releases/#{release.id}/roll_out", params: { shop_ids: [ @shop.id ] }

    # Exactly what the desktop sends once it has installed the new build.
    post "/api/license/check",
      params: { license: @shop.license.license_number, machineFingerprint: "A", agentVersion: "1.0.1" },
      as: :json
    assert_response :success

    get "/admin/agent_releases"
    assert_select "tbody tr td:nth-child(2)", text: "1"
    assert_select "tbody tr td:nth-child(3)", text: "1"
  end
end
