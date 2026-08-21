module Api
  class ShopsController < BaseController
    before_action :require_admin!

    def index
      now = Time.current
      shops = Shop.includes(:license).order(created_at: :desc)

      render json: {
        shops: shops.map { |shop|
          license = shop.license
          {
            id: shop.id,
            name: shop.name,
            createdAt: shop.created_at,
            licenseNumber: license&.license_number,
            expiresAt: license&.expires_at,
            lastCheckAt: license&.last_check_at,
            machineFingerprint: license&.machine_fingerprint,
            status: license ? license.status(now) : "no-license"
          }
        }
      }
    end

    def create
      name = params[:name]
      return render_error("name is required", status: :bad_request) if !name.is_a?(String) || name.strip.empty?

      months = params[:months].nil? ? 1 : params[:months]
      months = Integer(months, exception: false) if months.is_a?(String)
      unless months.is_a?(Integer) && months.between?(1, 120)
        return render_error("months must be an integer 1-120", status: :bad_request)
      end

      shop = Shop.create_with_license!(name:, months:)
      AppLog.info("shop.created", shopId: shop.id, licenseNumber: shop.license.license_number, name: shop.name, months:)

      render json: {
        shop: {
          id: shop.id,
          name: shop.name,
          createdAt: shop.created_at,
          license: { licenseNumber: shop.license.license_number, expiresAt: shop.license.expires_at }
        }
      }, status: :created
    end

    def show
      shop = Shop.includes(:license).find_by(id: params[:id])
      return render_error("Shop not found", status: :not_found) if shop.nil?

      now = Time.current
      license = shop.license

      render json: {
        shop: {
          id: shop.id,
          name: shop.name,
          createdAt: shop.created_at,
          license: license && {
            licenseNumber: license.license_number,
            expiresAt: license.expires_at,
            status: license.status(now),
            graceDaysRemaining: license.grace_days_remaining(now),
            machineFingerprint: license.machine_fingerprint,
            lastCheckAt: license.last_check_at,
            lastResetAt: license.last_reset_at
          }
        }
      }
    end

    # Renames a shop. The licence number is deliberately not editable: it is printed on QR
    # codes and configured into desktop services, so it stays fixed for the life of the shop.
    def update
      name = params[:name].is_a?(String) ? params[:name].strip : ""
      return render_error("name is required", status: :bad_request) if name.empty?
      return render_error("name must be 120 characters or fewer", status: :bad_request) if name.length > 120

      shop = Shop.find_by(id: params[:id])
      return render_error("Shop not found", status: :not_found) if shop.nil?

      previous = shop.name
      shop.update!(name:)
      AppLog.info("shop.renamed", shopId: shop.id, from: previous, to: shop.name)

      render json: { shop: { id: shop.id, name: shop.name } }
    end
  end
end
