class Shop < ApplicationRecord
  has_one :license, dependent: :destroy
  has_many :upload_sessions, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }

  # prepend, or the has_many above destroys the rows first - and those rows are the only
  # record that these objects exist. R2 would then hold bytes nothing can ever find.
  before_destroy :purge_r2_objects, prepend: true

  # What the admin UI shows: an admin switching the shop off wins over licence expiry.
  def status
    return "inactive" unless active?

    license&.status || "no licence"
  end

  def self.ransackable_attributes(_auth = nil) = %w[id name target_agent_version created_at updated_at]
  def self.ransackable_associations(_auth = nil) = %w[license upload_sessions]

  # A shop is meaningless without its licence, so the two rows are one transaction.
  # The unique index is the real guard against a duplicate licence number; retry the
  # astronomically unlikely collision rather than handing the admin a 500.
  def self.create_with_license!(name:, months:, now: Time.current)
    3.times do |attempt|
      begin
        return transaction do
          shop = create!(name: name.strip)
          shop.create_license!(
            license_number: License.generate_number,
            expires_at: License.extended_expiry(now, months, now)
          )
          shop
        end
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
        raise error unless error.message.include?("license_number")

        AppLog.warn("shop.license_number_collision", attempt:)
      end
    end

    raise "Could not allocate a licence number"
  end

  private

  # Deleting a shop is rare and manual; failing it because R2 was unreachable would be
  # worse than the leak, so this logs and lets the delete through.
  def purge_r2_objects
    keys = upload_sessions.where(purged_at: nil).pluck(:object_key)
    R2.delete_objects(keys)
    AppLog.info("shop.purged", shopId: id, count: keys.size) if keys.any?
  rescue StandardError => error
    AppLog.warn("shop.purge_failed", shopId: id, error: error.message)
  end
end
