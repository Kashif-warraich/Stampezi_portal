require "test_helper"

class AgentUpdateTest < ActionDispatch::IntegrationTest
  setup do
    @shop = Shop.create_with_license!(name: "Test Shop", months: 1)
    @license = @shop.license.license_number
    @admin = { "Authorization" => "Bearer #{ENV.fetch('ADMIN_TOKEN', 'test-token')}" }
    @sha = "a" * 64
    @deleted = []
  end

  # R2 is the only thing here that would touch the network: head_object to confirm the
  # upload landed, delete_object to prune. Everything else is local signing. Minitest 6
  # dropped Object#stub, and swapping the singleton method is all it ever did - no gem
  # needed for two methods.
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

  def publish!(version)
    post "/api/agent-releases", params: { version:, sha256: @sha }, headers: @admin, as: :json
    assert_response :success
    id = response.parsed_body["id"]

    without_r2 { post "/api/agent-releases/#{id}/publish", headers: @admin, as: :json }
    assert_response :success
    AgentRelease.find(id)
  end

  def check(agent_version: nil)
    params = { license: @license, machineFingerprint: "A" }
    params[:agentVersion] = agent_version if agent_version
    post "/api/license/check", params:, as: :json
    response.parsed_body
  end

  test "publishing a release needs the admin token" do
    post "/api/agent-releases", params: { version: "1.0.0", sha256: @sha }, as: :json
    assert_response :unauthorized
  end

  test "a malformed version or digest is refused" do
    post "/api/agent-releases", params: { version: "v1", sha256: @sha }, headers: @admin, as: :json
    assert_response :unprocessable_content

    post "/api/agent-releases", params: { version: "1.0.0", sha256: "nope" }, headers: @admin, as: :json
    assert_response :unprocessable_content
  end

  test "a release is not offered until its upload is confirmed" do
    post "/api/agent-releases", params: { version: "1.0.1", sha256: @sha }, headers: @admin, as: :json
    assert_response :success
    @shop.update!(target_agent_version: "1.0.1")

    # The row exists but nothing has landed in R2 yet.
    assert_nil check(agent_version: "1.0.0")["targetVersion"]
  end

  test "a published version is immutable, but a failed upload can be retried" do
    post "/api/agent-releases", params: { version: "1.0.0", sha256: @sha }, headers: @admin, as: :json
    assert_response :success
    # Same version again while unpublished: a retry, not a conflict.
    post "/api/agent-releases", params: { version: "1.0.0", sha256: @sha }, headers: @admin, as: :json
    assert_response :success

    publish!("1.0.1")
    post "/api/agent-releases", params: { version: "1.0.1", sha256: @sha }, headers: @admin, as: :json
    assert_response :conflict
  end

  test "the agent is told what the portal targets, not simply what is newest" do
    %w[1.0.0 1.0.1 1.0.2].each { |version| publish!(version) }

    # Frozen by default: publishing arms nothing, so nothing is offered.
    assert_nil check(agent_version: "1.0.0")["targetVersion"]

    # Staged at 1.0.1 while 1.0.2 exists - the whole point of the rollout control.
    @shop.update!(target_agent_version: "1.0.1")
    body = check(agent_version: "1.0.0")
    assert_equal "1.0.1", body["targetVersion"]
    assert_equal @sha, body["sha256"]
    assert_includes body["downloadUrl"], "agent/1.0.1/StampeziSetup.exe"

    # Already on target: nothing to do.
    assert_nil check(agent_version: "1.0.1")["targetVersion"]
  end

  test "rolling back is just pointing a shop at an older release" do
    publish!("1.0.0")
    publish!("1.0.1")
    @shop.update!(target_agent_version: "1.0.0")

    # Newer than its target, so it installs the older one - which is why the agent
    # compares for difference rather than for "is there something newer".
    assert_equal "1.0.0", check(agent_version: "1.0.1")["targetVersion"]
  end

  test "a target that was never published is not sent to the shop" do
    @shop.update!(target_agent_version: "9.9.9")
    assert_nil check(agent_version: "1.0.0")["targetVersion"]
  end

  test "the running version is recorded for the fleet view" do
    check(agent_version: "1.0.3")
    assert_equal "1.0.3", @shop.license.reload.agent_version

    # A client that predates agentVersion must not blank out what an upgraded one recorded.
    check
    assert_equal "1.0.3", @shop.license.reload.agent_version
  end

  test "R2 keeps the newest three builds and prunes the rest" do
    %w[1.0.0 1.0.1 1.0.2].each { |version| publish!(version) }
    assert_empty @deleted

    publish!("1.0.3")
    assert_equal [ "agent/1.0.0/StampeziSetup.exe" ], @deleted
    assert AgentRelease.find_by(version: "1.0.0").pruned?
    assert_equal %w[1.0.1 1.0.2 1.0.3], AgentRelease.installable.map(&:version).sort
  end

  test "pruning is by version order, not upload order" do
    %w[1.0.9 1.0.10 1.0.11].each { |version| publish!(version) }
    publish!("1.0.8")

    # 1.0.8 is the oldest despite being published last. Sorted as text it would look
    # like the newest of the four.
    assert_equal [ "agent/1.0.8/StampeziSetup.exe" ], @deleted
  end

  test "a version a shop is still targeted at is never pruned" do
    %w[1.0.0 1.0.1 1.0.2].each { |version| publish!(version) }
    @shop.update!(target_agent_version: "1.0.0")

    publish!("1.0.3")
    assert_empty @deleted, "pruning it would strand the shop with nothing to install"
    assert AgentRelease.find_by(version: "1.0.0").installable?
  end
end
