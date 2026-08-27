class UploadSession < ApplicationRecord
  # The one age that decides everything about a customer's file: how far back the desktop's
  # poll looks, how long a claim can be handed back, and how long the bytes stay in R2.
  # Anything older is the shop's problem, not a pending job.
  #
  # Half an hour matches what the desktop already does with the file once it has it
  # (RetentionMinutes, also 30), so a job is "fresh" for the same length of time on both
  # sides. The cost of shortening it is that a shop PC switched off for longer than this
  # never receives what was sent while it was down.
  PENDING_WINDOW = 30.minutes

  belongs_to :shop

  def self.ransackable_attributes(_auth = nil)
    %w[id shop_id status file_name object_key created_at delivered_at]
  end

  def self.ransackable_associations(_auth = nil) = %w[shop]

  scope :pending_for, ->(shop_id) {
    where(shop_id:, status: "Uploaded").where(created_at: PENDING_WINDOW.ago..).order(created_at: :asc)
  }

  # R2 is the passing medium, not the filing cabinet. Once a file can no longer reach a
  # desktop it is storage nobody will ever read again, billed monthly forever.
  #
  # "Can no longer reach a desktop" is exactly PENDING_WINDOW with no activity: pending_for
  # stops offering a session at that age and release stops resurrecting one. updated_at
  # rather than created_at because a claim bumps it - so a 40 MB download still in flight
  # holds its own object open instead of having it deleted out from under the shop.
  PURGE_BATCH = 50

  scope :purgeable_for, ->(shop_id) {
    where(shop_id:, purged_at: nil).where(updated_at: ..PENDING_WINDOW.ago).limit(PURGE_BATCH)
  }

  # Deletes this shop's dead objects and marks the rows. Returns how many went.
  #
  # Never raises: this rides on the poll that delivers customers' files, and housekeeping
  # must not be able to stop that. A delete that fails is simply swept again next time.
  def self.purge_r2!(shop_id)
    rows = purgeable_for(shop_id).pluck(:id, :object_key)
    return 0 if rows.empty?

    R2.delete_objects(rows.map(&:last))
    where(id: rows.map(&:first)).update_all(purged_at: Time.current)

    AppLog.info("upload_session.purged", shopId: shop_id, count: rows.size)
    rows.size
  rescue StandardError => error
    AppLog.warn("upload_session.purge_failed", shopId: shop_id, error: error.message)
    0
  end
end
