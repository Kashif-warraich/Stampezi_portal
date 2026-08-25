module Api
  class LicensesController < BaseController
    # The shop's desktop service heartbeat. Public: the licence number is the credential.
    def check
      license_number = license_param(params[:license])
      fingerprint = params[:machineFingerprint]
      agent_version = params[:agentVersion].to_s.strip.presence

      if license_number.nil? || !fingerprint.is_a?(String)
        return render_error("license (10 digits) and machineFingerprint are required", status: :bad_request)
      end

      license = License.find_by(license_number:)
      return render_error("Licence not found", status: :not_found) if license.nil?

      now = Time.current
      mismatch = {
        status: "machine-mismatch",
        expiresAt: license.expires_at,
        serverTime: now,
        graceDaysRemaining: 0
      }

      if license.machine_fingerprint.present? && license.machine_fingerprint != fingerprint
        AppLog.warn("license_check.machine_mismatch", license: license_number)
        return render json: mismatch
      end

      first_time = license.machine_fingerprint.nil?

      # First-time binding and the heartbeat are one write. The nil guard makes the binding
      # a claim: a second machine racing the first loses instead of rebinding.
      scope = License.where(license_number:)
      scope = first_time ? scope.where(machine_fingerprint: nil) : scope.where(machine_fingerprint: fingerprint)

      # Only written when the agent actually reported one, so a client that predates
      # agentVersion does not blank out what an upgraded one recorded.
      attributes = { machine_fingerprint: fingerprint, last_check_at: now, updated_at: now }
      attributes[:agent_version] = agent_version if agent_version
      changed = scope.update_all(attributes)

      if changed.zero?
        AppLog.warn("license_check.machine_mismatch", license: license_number, reason: "lost-binding-race")
        return render json: mismatch
      end

      grace = license.grace_days_remaining(now)
      status = license.check_status(now)

      AppLog.info("license_check.ok",
        license: license_number, status:, graceDaysRemaining: grace,
        bound: first_time ? "first-time" : "existing")

      render json: {
        status:, expiresAt: license.expires_at, serverTime: now, graceDaysRemaining: grace
      }.merge(update_instruction(license, agent_version))
    end

    def extend_license
      return unless require_admin!

      license_number = license_param(params[:license])
      months = params[:months]
      months = Integer(months, exception: false) if months.is_a?(String)

      unless license_number && months.is_a?(Integer) && months.between?(1, 120)
        return render_error("license (10 digits) and months (integer 1-120) are required", status: :bad_request)
      end

      license = License.find_by(license_number:)
      return render_error("Licence not found", status: :not_found) if license.nil?

      from = license.expires_at
      license.update!(expires_at: License.extended_expiry(from, months))

      AppLog.info("license_extend.applied",
        license: license_number, months:, from: from.utc.iso8601(3), to: license.expires_at.utc.iso8601(3))

      render json: { license: license_number, expiresAt: license.expires_at }
    end

    # A shop that reinstalls on a new PC needs its binding cleared, but not on demand
    # forever: the cooldown is what stops one licence quietly running on many machines.
    def reset_binding
      return unless require_admin!

      license_number = license_param(params[:license])
      return render_error("license (10 digits) is required", status: :bad_request) if license_number.nil?

      license = License.find_by(license_number:)
      return render_error("Licence not found", status: :not_found) if license.nil?

      now = Time.current
      next_allowed_at = license.last_reset_at && (license.last_reset_at + RESET_COOLDOWN)

      if next_allowed_at && next_allowed_at > now
        return render_error("Binding was reset less than 30 days ago", status: :bad_request, nextAllowedAt: next_allowed_at)
      end

      previous = license.machine_fingerprint
      license.update!(machine_fingerprint: nil, last_reset_at: now)

      AppLog.info("license_reset.applied", license: license_number, previousFingerprint: previous)

      render json: { license: license_number, machineFingerprint: nil, lastResetAt: now }
    end

    RESET_COOLDOWN = 30.days

    # The agent gets two hours to use this. It may sit on a jitter delay first, and then
    # pull 230 MB down a shop's DSL line.
    UPDATE_URL_TTL = 2 * 60 * 60

    private

    # The portal decides what a shop should run; the agent never compares itself against
    # "latest". That is the whole of the staged rollout - and because the agent installs
    # whatever differs from its own version rather than whatever is newer, pointing a shop
    # back at an older release is how a bad build gets pulled.
    def update_instruction(license, agent_version)
      target = license.shop.target_agent_version
      return {} if target.blank? || target == agent_version

      release = AgentRelease.installable.find_by(version: target)
      if release.nil?
        # Targeted at something unpublished or already pruned. Say so in the log rather
        # than sending the shop after a URL that will 404.
        AppLog.warn("agent_update.target_unavailable",
          license: license.license_number, target:, running: agent_version)
        return {}
      end

      AppLog.info("agent_update.offered",
        license: license.license_number, from: agent_version, to: release.version)

      {
        targetVersion: release.version,
        downloadUrl: R2.presigned_get_url(release.object_key, expires_in: UPDATE_URL_TTL),
        sha256: release.sha256,
        sizeBytes: release.size_bytes
      }
    end
  end
end
