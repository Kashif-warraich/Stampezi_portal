require "test_helper"

class LicenseTest < ActiveSupport::TestCase
  # A licence never exists without a shop (belongs_to, NOT NULL), and grace/check_status
  # read the shop's active flag.
  def licence(expires_at, active: true)
    License.new(expires_at:, shop: Shop.new(name: "Test Shop", active:))
  end

  test "generated numbers are 10 digits with no leading zero" do
    200.times { assert_match(/\A[1-9][0-9]{9}\z/, License.generate_number) }
  end

  test "grace runs out five days after expiry" do
    now = Time.utc(2026, 8, 20, 12)

    assert_equal 5, licence(now + 1.day).grace_days_remaining(now)
    assert_equal 5, licence(now - 1.second).grace_days_remaining(now)
    assert_equal 1, licence(now - 4.days).grace_days_remaining(now)
    assert_equal 0, licence(now - 5.days).grace_days_remaining(now)
    assert_equal 0, licence(now - 40.days).grace_days_remaining(now)
  end

  test "status and check_status agree except on the unexpired name" do
    now = Time.utc(2026, 8, 20, 12)

    unexpired = licence(now + 1.day)
    assert_equal "active", unexpired.status(now)
    # The deployed .NET service matches on "valid" - renaming this breaks every shop.
    assert_equal "valid", unexpired.check_status(now)

    assert_equal "grace", licence(now - 1.day).status(now)
    assert_equal "expired", licence(now - 10.days).status(now)
  end

  test "an inactive shop reads expired to the desktop, whatever the expiry date" do
    now = Time.utc(2026, 8, 20, 12)
    switched_off = licence(now + 100.days, active: false)

    assert_equal "expired", switched_off.check_status(now)
    assert_equal 0, switched_off.grace_days_remaining(now)
  end

  test "extending early never shortens a licence" do
    now = Time.utc(2026, 8, 20, 12)
    far = now + 100.days

    # Extends from the later of expiry and now, so the remaining time is kept.
    assert_equal far + 30.days, License.extended_expiry(far, 1, now)
    assert_equal now + 60.days, License.extended_expiry(now - 50.days, 2, now)
  end
end
