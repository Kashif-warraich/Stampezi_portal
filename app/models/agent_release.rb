class AgentRelease < ApplicationRecord
  # Current plus two behind: enough to roll a bad release back twice, few enough that R2
  # stays tidy. Storage is the only thing pruning saves - R2 egress is free, so a hundred
  # shops downloading the same 230 MB costs nothing.
  KEEP_OBJECTS = 3

  VERSION_FORMAT = /\A\d+\.\d+\.\d+\z/
  SHA256_FORMAT  = /\A[0-9a-f]{64}\z/

  validates :version,    presence: true, uniqueness: true, format: { with: VERSION_FORMAT }
  validates :sha256,     format: { with: SHA256_FORMAT }
  validates :object_key, presence: true

  scope :published, -> { where.not(published_at: nil) }
  # What a shop can actually be sent: uploaded, confirmed, and still in R2.
  scope :installable, -> { published.where(pruned_at: nil) }

  def self.ransackable_attributes(_auth = nil)
    %w[version sha256 size_bytes published_at pruned_at created_at]
  end

  def self.ransackable_associations(_auth = nil) = []

  # Semver order, which Postgres cannot do on a string column ("1.0.10" sorts below
  # "1.0.9" as text). Dozens of rows at most, so sorting in Ruby is free.
  def self.newest_first(scope = all)
    scope.to_a.sort_by { |release| Gem::Version.new(release.version) }.reverse
  end

  def installable? = published_at.present? && pruned_at.nil?
  def pruned?      = pruned_at.present?

  def targeted_by = Shop.where(target_agent_version: version)

  # Deleting a release a shop is pointed at would leave that shop asking the portal for a
  # build nobody can serve, forever.
  def deletable? = targeted_by.none?

  # Removes the R2 object if it is still there. Safe to call twice.
  def delete_object!
    return if pruned?

    R2.delete_object(object_key)
    update!(pruned_at: Time.current)
  end

  # Deletes the R2 object for every published release past the newest KEEP_OBJECTS. A
  # version some shop is still pointed at is never pruned, however old: doing so would
  # strand that shop with an update it can never download.
  def self.prune_objects!
    keep     = newest_first(published).first(KEEP_OBJECTS).map(&:id)
    targeted = Shop.where.not(target_agent_version: nil).distinct.pluck(:target_agent_version)
    pruned   = 0

    published.where(pruned_at: nil).where.not(id: keep).find_each do |release|
      if targeted.include?(release.version)
        AppLog.info("agent_release.prune_skipped", version: release.version, reason: "still-targeted")
        next
      end

      R2.delete_object(release.object_key)
      release.update!(pruned_at: Time.current)
      pruned += 1
      AppLog.info("agent_release.pruned", version: release.version, objectKey: release.object_key)
    end

    pruned
  end
end
