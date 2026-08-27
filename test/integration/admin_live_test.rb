require "test_helper"

# The fleet view. Everything on it is derived from licenses.last_check_at, so these tests
# move that one timestamp and check what the page says about it.
class AdminLiveTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "boss@stampezi.it", password: "secret-one")
    post "/admin/login", params: { email: @user.email, password: "secret-one" }
    follow_redirect!
  end

  def shop_with_check_in(name, last_check_at)
    shop = Shop.create_with_license!(name:, months: 1)
    shop.license.update!(last_check_at:)
    shop
  end

  test "it needs a signed-in admin" do
    get "/admin/logout"
    get "/admin/live"
    assert_redirected_to login_path(next: "/admin/live")
  end

  test "each shop is classified by how long ago it last checked in" do
    shop_with_check_in("Fresh", 1.minute.ago)
    shop_with_check_in("Quiet", 20.minutes.ago)
    shop_with_check_in("Silent", 3.days.ago)
    Shop.create_with_license!(name: "Unopened", months: 1)   # never checked in

    get "/admin/live"
    assert_response :success

    assert_select ".badge", text: "live"
    assert_select ".badge", text: "quiet"
    assert_select ".badge", text: "not checking in"
    assert_select ".badge", text: "never seen"
  end

  # The page exists to be scanned for trouble, so trouble must not be below the fold.
  test "broken shops sort above healthy ones" do
    shop_with_check_in("Aaa healthy", 1.minute.ago)
    shop_with_check_in("Zzz broken", 2.days.ago)

    get "/admin/live"
    names = css_select("tbody tr td .strong").map(&:text)

    assert_equal [ "Zzz broken", "Aaa healthy" ], names
  end

  test "a licence check moves a shop straight into live" do
    shop = shop_with_check_in("Recovering", 3.days.ago)

    get "/admin/live"
    assert_select ".badge", text: "not checking in"

    post "/api/license/check",
      params: { license: shop.license.license_number, machineFingerprint: "A" }, as: :json
    assert_response :success

    get "/admin/live"
    assert_select ".badge", text: "live"
    assert_select ".badge", text: "not checking in", count: 0
  end
end
