class Shop < ApplicationRecord
  has_one :license, dependent: :destroy
  has_many :upload_sessions, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }

  def self.ransackable_attributes(_auth = nil) = %w[id name created_at updated_at]
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
end
