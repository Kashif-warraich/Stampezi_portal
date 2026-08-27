class License < ApplicationRecord
  GRACE_DAYS = 5
  # 10 digits, never starting with 0 so it always reads back as the same number.
  NUMBER_FORMAT = /\A[1-9][0-9]{9}\z/

  belongs_to :shop

  validates :license_number, presence: true, uniqueness: true, format: { with: NUMBER_FORMAT }
  validates :expires_at, presence: true

  def self.ransackable_attributes(_auth = nil)
    %w[id license_number shop_id expires_at machine_fingerprint agent_version last_check_at last_reset_at created_at]
  end

  def self.ransackable_associations(_auth = nil) = %w[shop]

  # SecureRandom, not rand: this is what a phone sends to claim an upload slot.
  def self.generate_number
    (SecureRandom.random_number(9_000_000_000) + 1_000_000_000).to_s
  end

  # Rejects junk before it reaches the database.
  def self.number?(value)
    value.is_a?(String) && value.match?(NUMBER_FORMAT)
  end

  # Extends from whichever is later, so extending early never shortens a licence.
  def self.extended_expiry(current, months, now = Time.current)
    [ current, now ].max + (months * 30).days
  end

  # Days of grace left after expiry: full 5 on the expiry day, 0 once burned through.
  # A deactivated shop gets none - grace is for late payers, not switched-off shops.
  def grace_days_remaining(now = Time.current)
    return 0 unless shop.active?
    return GRACE_DAYS if expires_at > now

    [ GRACE_DAYS - ((now - expires_at) / 1.day).floor, 0 ].max
  end

  # A shop's agent checks in every LicenseCheckIntervalMinutes - 1 by default, set in each
  # shop's setup.ini, which is why these are generous fixed windows rather than a multiple
  # of an interval this side cannot see. Five missed checks is a shop worth glancing at; an
  # hour of silence is one worth phoning.
  LIVE_WITHIN = 5.minutes
  LATE_WITHIN = 1.hour

  # Deliberately about check-ins, not about the service. From here a stopped service, a PC
  # switched off, a dead router and an unplugged network cable are the same event, and the
  # portal must not claim to tell them apart - the wording in the UI says "not checking in"
  # for that reason.
  def agent_state(now = Time.current)
    return "never" if last_check_at.nil?
    return "live"  if last_check_at > LIVE_WITHIN.ago(now)
    return "late"  if last_check_at > LATE_WITHIN.ago(now)

    "down"
  end

  # What the admin list shows.
  def status(now = Time.current)
    return "active" if expires_at > now

    grace_days_remaining(now).positive? ? "grace" : "expired"
  end

  # What the desktop service is told. Same three states, but an unexpired licence reads
  # "valid" here - the deployed .NET client matches on that exact string. An inactive shop
  # reads "expired" whatever the expiry date, so deactivating a shop in the portal stops
  # its desktop on the next check - and refuse_expired! then blocks its file endpoints too.
  def check_status(now = Time.current)
    return "expired" unless shop.active?
    return "valid" if expires_at > now

    grace_days_remaining(now).positive? ? "grace" : "expired"
  end
end
