ActiveAdmin.register License do
  menu priority: 3, label: "Licences"

  # Read-only on purpose. The number is printed on QR codes and configured into desktop
  # services, and expiry moves through the Extend action so it is always logged.
  actions :index, :show

  filter :license_number
  filter :shop_id, as: :select, collection: -> { Shop.order(:name).pluck(:name, :id) }, label: "Shop"
  filter :expires_at
  filter :machine_fingerprint, label: "Machine fingerprint"
  filter :last_check_at

  index do
    column("Number") { |licence| link_to licence.license_number, admin_license_path(licence) }
    column("Shop") { |licence| link_to licence.shop.name, admin_shop_path(licence.shop) }
    column("Status") { |licence| status_tag licence.status }
    column :expires_at
    column("Bound") { |licence| licence.machine_fingerprint.present? ? "yes" : "no" }
    column :last_check_at
    actions
  end

  show do
    attributes_table do
      row("Number") { resource.license_number }
      row("Shop") { link_to resource.shop.name, admin_shop_path(resource.shop) }
      row("Status") { status_tag resource.status }
      row("Grace days remaining") { resource.grace_days_remaining }
      row :expires_at
      row("Machine") { resource.machine_fingerprint || "not bound" }
      row :last_check_at
      row :last_reset_at
    end
  end
end
