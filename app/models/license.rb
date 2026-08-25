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
  def grace_days_remaining(now = Time.current)
    return GRACE_DAYS if expires_at > now

    [ GRACE_DAYS - ((now - expires_at) / 1.day).floor, 0 ].max
  end

  # What the admin list shows.
  def status(now = Time.current)
    return "active" if expires_at > now

    grace_days_remaining(now).positive? ? "grace" : "expired"
  end

  # What the desktop service is told. Same three states, but an unexpired licence reads
  # "valid" here - the deployed .NET client matches on that exact string.
  def check_status(now = Time.current)
    return "valid" if expires_at > now

    grace_days_remaining(now).positive? ? "grace" : "expired"
  end
end
