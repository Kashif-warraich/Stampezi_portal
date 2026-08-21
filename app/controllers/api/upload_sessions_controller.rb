module Api
  class UploadSessionsController < BaseController
    EXPIRES_IN_SECONDS = 300

    def create
      # The shop comes from the cookie the QR link set, never from the body: a customer's
      # page cannot ask for an upload slot on some other shop's behalf.
      license_number = license_param(cookies.encrypted[UploadsController::LICENSE_COOKIE])
      if license_number.nil?
        return render_error("Scan the shop's QR code again", status: :unauthorized)
      end

      file_name = params[:fileName]
      return render_error("fileName is required", status: :bad_request) unless file_name.is_a?(String)

      unless UploadRules.allowed?(file_name)
        AppLog.warn("upload_session.rejected", reason: "extension", fileName: file_name)
        return render_error("File type not allowed. Allowed: #{UploadRules::ALLOWED_EXTENSIONS.join(', ')}", status: :bad_request)
      end

      license = License.find_by(license_number:)
      if license.nil?
        AppLog.warn("upload_session.rejected", reason: "unknown-license")
        return render_error("Shop not found", status: :not_found)
      end

      shop_id = license.shop_id
      session_id = SecureRandom.uuid

      UploadSession.create!(
        id: session_id,
        shop_id:,
        status: "Pending",
        file_name:,
        object_key: R2.object_key_for(shop_id, session_id, file_name)
      )

      AppLog.info("upload_session.created", sessionId: session_id, license: license_number, shopId: shop_id, fileName: file_name)

      render json: {
        sessionId: session_id,
        presignedPutUrl: R2.presigned_put_url(shop_id, session_id, file_name),
        expiresInSeconds: EXPIRES_IN_SECONDS
      }
    end
  end
end
