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
  end
end
