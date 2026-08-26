module Admin
  class ShopsController < BaseController
    FILTERS = %w[all active grace expired inactive].freeze

    before_action :set_shop, only: %i[show edit update destroy qr extend_license reset_binding]

    def index
      @q = params[:q].to_s.strip
      @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "all"
      @total = Shop.count

      shops = Shop.includes(:license).order(:name)
      shops = shops.where("name ILIKE ?", "%#{Shop.sanitize_sql_like(@q)}%") if @q.present?
      # Shop status is computed in Ruby (active flag + expiry + grace), so the chip filter is too.
      @shops = shops.select { |shop| @filter == "all" || shop.status == @filter }
    end

    def show
      @uploads = @shop.upload_sessions.order(created_at: :desc).limit(25)
    end

    def new; end

    # A shop is meaningless without its licence, so creation goes through the model's
    # transaction rather than a plain Shop.create.
    def create
      months = params.dig(:shop, :months).presence&.to_i || 1
      shop = Shop.create_with_license!(name: params.dig(:shop, :name).to_s, months: months.clamp(1, 120))
      AppLog.info("shop.created", shopId: shop.id, licenseNumber: shop.license.license_number,
        name: shop.name, months:)

      redirect_to admin_shop_path(shop), notice: "Shop created"
    rescue ActiveRecord::RecordInvalid => error
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end

    def edit; end

    def update
      previous_name = @shop.name
      was_active = @shop.active?
      expires_on = params.dig(:shop, :license_expires_on).presence

      Shop.transaction do
        @shop.update!(params.require(:shop).permit(:name, :active))

        if expires_on && (licence = @shop.license)
          new_expiry = Date.parse(expires_on).in_time_zone.end_of_day
          if licence.expires_at != new_expiry
            from = licence.expires_at
            licence.update!(expires_at: new_expiry)
            AppLog.info("license_expiry.set", license: licence.license_number,
              from: from.utc.iso8601(3), to: new_expiry.utc.iso8601(3))
          end
        end
      end

      AppLog.info("shop.renamed", shopId: @shop.id, from: previous_name, to: @shop.name) if previous_name != @shop.name
      AppLog.info("shop.#{@shop.active? ? 'activated' : 'deactivated'}", shopId: @shop.id, name: @shop.name) if was_active != @shop.active?

      redirect_to admin_shop_path(@shop), notice: "Shop updated"
    rescue ActiveRecord::RecordInvalid => error
      flash.now[:alert] = error.record.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    rescue ArgumentError
      flash.now[:alert] = "Licence expiry must be a valid date"
      render :edit, status: :unprocessable_entity
    end

    def destroy
      name = @shop.name
      @shop.destroy!
      AppLog.info("shop.deleted", shopId: @shop.id, name:)
      redirect_to admin_shops_path, notice: "Deleted #{name}"
    end

    # The counter card. Rendered big enough to print without the modules going fuzzy.
    def qr
      url = upload_url(l: @shop.license.license_number)
      png = RQRCode::QRCode.new(url, level: :m).as_png(size: 1024, border_modules: 2)

      send_data png.to_s, type: "image/png", disposition: "attachment",
        filename: "stampezi-#{@shop.name.parameterize}-#{@shop.license.license_number}.png"
    end

    def extend_license
      months = params[:months].to_i.clamp(1, 120)
      licence = @shop.license
      from = licence.expires_at
      licence.update!(expires_at: License.extended_expiry(from, months))
      AppLog.info("license_extend.applied", license: licence.license_number, months:,
        from: from.utc.iso8601(3), to: licence.expires_at.utc.iso8601(3))

      redirect_to admin_shop_path(@shop), notice: "Extended by #{months} month(s)"
    end

    def reset_binding
      licence = @shop.license
      next_allowed_at = licence.last_reset_at && (licence.last_reset_at + Api::LicensesController::RESET_COOLDOWN)

      if next_allowed_at && next_allowed_at > Time.current
        redirect_to admin_shop_path(@shop), alert: "Binding was reset less than 30 days ago"
      else
        previous = licence.machine_fingerprint
        licence.update!(machine_fingerprint: nil, last_reset_at: Time.current)
        AppLog.info("license_reset.applied", license: licence.license_number, previousFingerprint: previous)

        redirect_to admin_shop_path(@shop), notice: "Machine binding cleared"
      end
    end

    private

    def set_shop
      @shop = Shop.find(params[:id])
    end
  end
end
