module Api
  class UploadCompletionsController < BaseController
    def create
      session_id = params[:sessionId]
      return render_error("sessionId is required", status: :bad_request) unless session_id.is_a?(String)

      upload = UploadSession.find_by(id: session_id)
      return render_error("Session not found", status: :not_found) if upload.nil?

      size = R2.object_size(upload.object_key)
      return render_error("Object not found in storage", status: :conflict) if size.nil?

      # The browser's 50MB check is advice, not enforcement - the presigned PUT goes
      # straight to R2. This is where an oversized file actually gets rejected.
      if size > UploadRules::MAX_UPLOAD_BYTES
        R2.delete_object(upload.object_key)
        AppLog.warn("upload_complete.too_large", sessionId: session_id, shopId: upload.shop_id, size:)
        return render_error("File is too large", status: :payload_too_large)
      end

      # Only Pending advances, so a replayed call can't drag a Delivered row back to Uploaded.
      changed = UploadSession.where(id: session_id, status: "Pending")
                             .update_all(status: "Uploaded", updated_at: Time.current)
      if changed.zero?
        return render_error("Session is #{upload.status}, not Pending", status: :conflict)
      end

      AppLog.info("upload_complete.uploaded", sessionId: session_id, shopId: upload.shop_id, fileName: upload.file_name, size:)

      render json: { success: true }
    end
  end
end
