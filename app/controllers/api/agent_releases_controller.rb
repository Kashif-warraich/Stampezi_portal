module Api
  # Publishing a new desktop build. Driven from the build machine with the admin bearer
  # token, not from a browser: the installer is ~230 MB and has no business travelling
  # through a Render web dyno when a presigned PUT sends it straight to R2.
  class AgentReleasesController < BaseController
    # Long enough to push 230 MB up a normal office connection.
    UPLOAD_WINDOW = 2 * 60 * 60

    def create
      return unless require_admin!

      version = params[:version].to_s.strip
      sha256  = params[:sha256].to_s.strip.downcase

      # Re-issuing the slot for a version whose upload never completed is a retry, not a
      # conflict. A published one is immutable - cut a new version instead.
      release = AgentRelease.find_by(version:)
      if release&.published_at.present?
        return render_error("#{version} is already published", status: :conflict)
      end

      release ||= AgentRelease.new(version:)
      release.assign_attributes(sha256:, notes: params[:notes], object_key: R2.agent_release_key(version))

      unless release.save
        return render_error(release.errors.full_messages.to_sentence, status: :unprocessable_content)
      end

      AppLog.info("agent_release.slot", version:, objectKey: release.object_key)

      render json: {
        id: release.id,
        version: release.version,
        objectKey: release.object_key,
        presignedPutUrl: R2.presigned_put(release.object_key, expires_in: UPLOAD_WINDOW),
        expiresInSeconds: UPLOAD_WINDOW
      }
    end

    # Confirms the bytes landed, then trims R2 back to the newest few builds.
    def publish
      return unless require_admin!

      release = AgentRelease.find_by(id: params[:id])
      return render_error("Release not found", status: :not_found) if release.nil?
      return render_error("Already published", status: :conflict) if release.published_at.present?

      size = R2.object_size(release.object_key)
      return render_error("Nothing was uploaded to #{release.object_key}", status: :conflict) if size.nil?

      release.update!(size_bytes: size, published_at: Time.current, pruned_at: nil)
      AppLog.info("agent_release.published", version: release.version, size:)

      pruned = AgentRelease.prune_objects!

      render json: {
        version: release.version,
        sizeBytes: size,
        publishedAt: release.published_at,
        prunedCount: pruned,
        # Publishing arms nothing by itself. Point shops at it from the admin, a few first.
        rolledOutTo: Shop.where(target_agent_version: release.version).count
      }
    end
  end
end
