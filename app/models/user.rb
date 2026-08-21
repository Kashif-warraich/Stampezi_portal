class User < ApplicationRecord
  # bcrypt via has_secure_password. Rails' default cost is deliberately slow, which is the
  # point of a password hash - and unlike Cloudflare Workers, a normal server has no
  # per-request CPU ceiling to trip over.
  has_secure_password

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true

  # What the admin UI is allowed to search and sort by. An allowlist, not a
  # convenience: password_digest must never be reachable through a query string.
  def self.ransackable_attributes(_auth = nil) = %w[id email created_at updated_at]
  def self.ransackable_associations(_auth = nil) = []
end
