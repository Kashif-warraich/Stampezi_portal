module Api
  class DownloadUrlsController < BaseController
    EXPIRES_IN_SECONDS = 300

    def create
      session_id = params[:session_id]

      # The licence number scopes the claim: a session id alone must not be enough to take
      # another shop's file. Still not authentication - it is a shared secret the desktop
      # holds. Swap for a per-shop token when the service gets credentials.
      license_number = license_param(params[:license])
      return render_error("license (10 digits) is required", status: :bad_request) if license_number.nil?

      license = License.find_by(license_number:)
      return render_error("Licence not found", status: :not_found) if license.nil?

      # The claim: one conditional UPDATE, so of two concurrent requests exactly one sees
      # changed == 1. A read-then-write pair would let both through.
      now = Time.current
      changed = UploadSession.where(id: session_id, shop_id: license.shop_id, status: "Uploaded")
                             .update_all(status: "Delivered", delivered_at: now, updated_at: now)

      if changed.zero?
        existing = UploadSession.find_by(id: session_id)

        # Wrong shop is indistinguishable from "no such session" on purpose: a caller must
        # not be able to probe for other shops' session ids.
        if existing.nil? || existing.shop_id != license.shop_id
          AppLog.warn("download_url.denied", sessionId: session_id, license: license_number,
            reason: existing ? "wrong-shop" : "not-found")
          return render_error("Session not found", status: :not_found)
        end

        AppLog.info("download_url.conflict", sessionId: session_id, license: license_number, status: existing.status)
        # Body carries its own "status" field (the session's), separate from the HTTP 409.
        return render json: { error: "already-delivered", status: existing.status }, status: :conflict
      end

      upload = UploadSession.find_by(id: session_id)
      return render_error("Session not found", status: :not_found) if upload.nil?

      AppLog.info("download_url.claimed", sessionId: session_id, license: license_number, objectKey: upload.object_key)

      render json: {
        downloadUrl: R2.presigned_get_url(upload.object_key),
        expiresInSeconds: EXPIRES_IN_SECONDS
      }
    end
  end
end
