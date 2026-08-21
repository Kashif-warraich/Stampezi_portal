ActiveAdmin.register Shop do
  menu priority: 2
  permit_params :name

  # New shops get a licence too, so the default form gains a months field.
  filter :name
  filter :created_at

  index do
    selectable_column
    column :name do |shop|
      link_to shop.name, admin_shop_path(shop)
    end
    column("Licence no.") { |shop| shop.license&.license_number }
    column("Status") do |shop|
      next status_tag("no licence") if shop.license.nil?

      status = shop.license.status
      status_tag status, class: { "active" => :ok, "grace" => :warning, "expired" => :error }[status]
    end
    column("Expires") { |shop| shop.license&.expires_at }
    column("Last check-in") { |shop| shop.license&.last_check_at }
    column("QR") { |shop| shop.license ? link_to("Download", qr_admin_shop_path(shop)) : nil }
    actions
  end

  show do
    attributes_table do
      row :name
      row :created_at
    end

    if resource.license
      licence = resource.license
      panel "Licence" do
        attributes_table_for licence do
          row("Number") { licence.license_number }
          row("Status") { status_tag licence.status }
          row("Grace days remaining") { licence.grace_days_remaining }
          row("Expires") { licence.expires_at }
          row("Machine") { licence.machine_fingerprint || "not bound" }
          row("Last check-in") { licence.last_check_at }
          row("Last binding reset") { licence.last_reset_at }
          row("QR code") { link_to "Download PNG", qr_admin_shop_path(resource) }
        end
      end
    end

    panel "Uploads" do
      table_for resource.upload_sessions.order(created_at: :desc).limit(25) do
        column("File") { |upload| upload.file_name }
        column("Status") { |upload| status_tag upload.status }
        column("Received") { |upload| upload.created_at }
        column("Delivered") { |upload| upload.delivered_at }
      end
    end
  end

  sidebar "Licence actions", only: :show do
    render "license_actions", shop: resource
  end

  form do |f|
    f.inputs do
      f.input :name
      # Only on create: the licence number is fixed for the life of the shop, and its
      # expiry is changed through the Extend action, not by editing a field.
      f.input :months, as: :number, label: "Initial licence (months)", input_html: { value: 1, min: 1, max: 120 } unless f.object.persisted?
    end
    f.actions
  end

  controller do
    # A shop is meaningless without its licence, so creation goes through the model's
    # transaction rather than ActiveAdmin's plain Shop.create.
    def create
      months = params[:shop][:months].presence&.to_i || 1
      shop = Shop.create_with_license!(name: params[:shop][:name].to_s, months: months.clamp(1, 120))
      AppLog.info("shop.created", shopId: shop.id, licenseNumber: shop.license.license_number,
        name: shop.name, months:)

      redirect_to admin_shop_path(shop), notice: "Shop created"
    rescue ActiveRecord::RecordInvalid => error
      redirect_to new_admin_shop_path, alert: error.record.errors.full_messages.to_sentence
    end

    def update
      previous = resource.name
      super do |success, _failure|
        success.html { AppLog.info("shop.renamed", shopId: resource.id, from: previous, to: resource.name) }
      end
    end
  end

  # The counter card. Rendered big enough to print without the modules going fuzzy.
  member_action :qr, method: :get do
    url = upload_url(l: resource.license.license_number)
    png = RQRCode::QRCode.new(url, level: :m).as_png(size: 1024, border_modules: 2)

    send_data png.to_s, type: "image/png", disposition: "attachment",
      filename: "stampezi-#{resource.name.parameterize}-#{resource.license.license_number}.png"
  end

  member_action :extend_license, method: :post do
    months = params[:months].to_i.clamp(1, 120)
    licence = resource.license
    from = licence.expires_at
    licence.update!(expires_at: License.extended_expiry(from, months))
    AppLog.info("license_extend.applied", license: licence.license_number, months:,
      from: from.utc.iso8601(3), to: licence.expires_at.utc.iso8601(3))

    redirect_to admin_shop_path(resource), notice: "Extended by #{months} month(s)"
  end

  member_action :reset_binding, method: :post do
    licence = resource.license
    next_allowed_at = licence.last_reset_at && (licence.last_reset_at + Api::LicensesController::RESET_COOLDOWN)

    if next_allowed_at && next_allowed_at > Time.current
      redirect_to admin_shop_path(resource), alert: "Binding was reset less than 30 days ago"
    else
      previous = licence.machine_fingerprint
      licence.update!(machine_fingerprint: nil, last_reset_at: Time.current)
      AppLog.info("license_reset.applied", license: licence.license_number, previousFingerprint: previous)

      redirect_to admin_shop_path(resource), notice: "Machine binding cleared"
    end
  end
end
