require "test_helper"

class LicenseTest < ActiveSupport::TestCase
  test "generated numbers are 10 digits with no leading zero" do
    200.times { assert_match(/\A[1-9][0-9]{9}\z/, License.generate_number) }
  end

  test "grace runs out five days after expiry" do
    now = Time.utc(2026, 8, 20, 12)
    license = License.new(expires_at: now - 1.second)

    assert_equal 5, License.new(expires_at: now + 1.day).grace_days_remaining(now)
    assert_equal 5, license.grace_days_remaining(now)
    assert_equal 1, License.new(expires_at: now - 4.days).grace_days_remaining(now)
    assert_equal 0, License.new(expires_at: now - 5.days).grace_days_remaining(now)
    assert_equal 0, License.new(expires_at: now - 40.days).grace_days_remaining(now)
  end

  test "status and check_status agree except on the unexpired name" do
    now = Time.utc(2026, 8, 20, 12)

    unexpired = License.new(expires_at: now + 1.day)
    assert_equal "active", unexpired.status(now)
    # The deployed .NET service matches on "valid" - renaming this breaks every shop.
    assert_equal "valid", unexpired.check_status(now)

    assert_equal "grace", License.new(expires_at: now - 1.day).status(now)
    assert_equal "expired", License.new(expires_at: now - 10.days).status(now)
  end

  test "extending early never shortens a licence" do
    now = Time.utc(2026, 8, 20, 12)
    far = now + 100.days

    # Extends from the later of expiry and now, so the remaining time is kept.
    assert_equal far + 30.days, License.extended_expiry(far, 1, now)
    assert_equal now + 60.days, License.extended_expiry(now - 50.days, 2, now)
  end
end
