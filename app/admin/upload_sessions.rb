ActiveAdmin.register UploadSession do
  menu priority: 4, label: "Uploads"

  # A file's life is driven by the customer's phone and the shop's desktop service.
  # Editing rows here would desynchronise them from what is actually in R2.
  actions :index, :show

  filter :shop_id, as: :select, collection: -> { Shop.order(:name).pluck(:name, :id) }, label: "Shop"
  filter :status, as: :select, collection: %w[Pending Uploaded Delivered Expired]
  filter :file_name
  filter :created_at

  scope :all, default: true
  scope("Waiting") { |scope| scope.where(status: "Uploaded") }
  scope("Delivered") { |scope| scope.where(status: "Delivered") }

  index do
    column("Shop") { |upload| link_to upload.shop.name, admin_shop_path(upload.shop) }
    column :file_name
    column("Status") { |upload| status_tag upload.status }
    column :created_at
    column :delivered_at
    actions
  end

  show do
    attributes_table do
      row("Shop") { link_to resource.shop.name, admin_shop_path(resource.shop) }
      row :file_name
      row("Status") { status_tag resource.status }
      row("Object key") { code resource.object_key }
      row :created_at
      row :delivered_at
    end
  end
end
