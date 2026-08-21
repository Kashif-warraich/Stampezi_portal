class UploadSession < ApplicationRecord
  # How far back the desktop's poll looks. Anything older is the shop's problem, not a
  # pending job.
  PENDING_WINDOW = 2.hours

  belongs_to :shop

  def self.ransackable_attributes(_auth = nil)
    %w[id shop_id status file_name object_key created_at delivered_at]
  end

  def self.ransackable_associations(_auth = nil) = %w[shop]

  scope :pending_for, ->(shop_id) {
    where(shop_id:, status: "Uploaded").where(created_at: PENDING_WINDOW.ago..).order(created_at: :asc)
  }
end
