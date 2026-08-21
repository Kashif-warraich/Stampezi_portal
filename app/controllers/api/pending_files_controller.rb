module Api
  # Polled by each shop's desktop service. Public: the licence number is the credential.
  class PendingFilesController < BaseController
    def index
      license_number = license_param(params[:license])
      return render_error("license (10 digits) is required", status: :bad_request) if license_number.nil?

      license = License.find_by(license_number:)
      return render_error("Licence not found", status: :not_found) if license.nil?

      # Only "Uploaded" is ever returned, so a Delivered or Expired session cannot come back.
      files = UploadSession.pending_for(license.shop_id).map do |upload|
        {
          id: upload.id,
          shopId: upload.shop_id,
          status: upload.status,
          fileName: upload.file_name,
          objectKey: upload.object_key,
          createdAt: upload.created_at,
          deliveredAt: upload.delivered_at
        }
      end

      AppLog.info("pending_files.served", license: license_number, count: files.size) if files.any?

      render json: { files: }
    end
  end
end
