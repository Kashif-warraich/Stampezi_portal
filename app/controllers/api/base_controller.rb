module Api
  # Every response here is JSON consumed by the admin pages, the customer's phone or the
  # shop's .NET service. The field names are camelCase and the timestamps are ISO 8601 with
  # milliseconds, exactly as the Next.js portal emitted them - the deployed desktop client
  # parses these, so the shapes are a contract, not a preference.
  class BaseController < ApplicationController
    # These endpoints authenticate by session cookie or bearer token, never by form token.
    skip_forgery_protection

    private

    def render_error(message, status:, **extra)
      render json: { error: message, **extra }, status:
    end

    def require_admin!
      return true if admin?

      render_error("Unauthorized", status: :unauthorized)
      false
    end

    def license_param(value)
      License.number?(value) ? value : nil
    end

    # Renders 403 and returns true when the licence is burned through. Grace still delivers -
    # a shop inside its five days gets warned, not cut off. Expiry is enforced here rather
    # than only as a toast on the shop's PC, so an unpatched desktop cannot ignore it.
    def refuse_expired!(license)
      return false unless license.check_status == "expired"

      AppLog.warn("license.expired_request", license: license.license_number, path: request.path)
      render_error("license-expired", status: :forbidden)
      true
    end
  end
end
