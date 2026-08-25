ActiveAdmin.register AgentRelease do
  menu priority: 5, label: "Releases"

  # No :new here - creating a release means moving 230 MB, which the Upload page does with
  # a presigned PUT straight to R2. Only the notes are editable afterwards: the version, the
  # object key and the digest describe bytes that already exist, and rewriting them would
  # just make the row lie about what a shop is going to download.
  actions :index, :show, :edit, :update, :destroy
  permit_params :notes

  filter :version
  filter :created_at

  scope :all, default: true
  scope("Installable") { |scope| scope.published.where(pruned_at: nil) }
  scope("Pruned")      { |scope| scope.where.not(pruned_at: nil) }

  action_item :upload, only: :index do
    link_to "Upload a release", upload_admin_agent_releases_path
  end

  index do
    column :version
    column("Shops on it") { |release| release.targeted_by.count }
    column("State") do |release|
      if release.pruned?         then status_tag "pruned", class: :error
      elsif release.installable? then status_tag "installable", class: :ok
      else                            status_tag "uploading", class: :warning
      end
    end
    column("Size") { |release| release.size_bytes ? "#{(release.size_bytes / 1024.0 / 1024).round} MB" : nil }
    column :published_at
    actions
  end

  show do
    attributes_table do
      row :version
      row("State") { status_tag(resource.pruned? ? "pruned" : resource.installable? ? "installable" : "uploading") }
      row("Size") { resource.size_bytes ? "#{(resource.size_bytes / 1024.0 / 1024).round} MB" : nil }
      row :object_key
      row("SHA-256") { code resource.sha256 }
      row :notes
      row :published_at
      row("Pruned from R2") { resource.pruned_at }
      row :created_at
    end

    panel "Shops targeted at this version" do
      table_for resource.targeted_by.order(:name) do
        column("Shop") { |shop| link_to shop.name, admin_shop_path(shop) }
        column("Running") { |shop| shop.license&.agent_version || "not reported" }
        column("Last check-in") { |shop| shop.license&.last_check_at }
      end
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs "Notes" do
      f.input :notes, hint: "The version, digest and object key describe bytes already in R2 and cannot be edited."
    end
    f.actions
  end

  collection_action :upload, method: :get do
    # Renders app/views/admin/agent_releases/upload.html.erb.
  end

  controller do
    # Deleting a release takes its installer out of R2 with it - the row alone is of no use
    # to anyone, and leaving the object behind is exactly the storage the pruning exists to
    # reclaim.
    def destroy
      release = resource

      if release.targeted_by.any?
        names = release.targeted_by.order(:name).limit(5).pluck(:name).join(", ")
        return redirect_to admin_agent_release_path(release),
          alert: "#{release.targeted_by.count} shop(s) are still targeted at #{release.version} (#{names}). Point them elsewhere first."
      end

      version = release.version
      release.delete_object!
      release.destroy!
      AppLog.info("agent_release.deleted", version:)

      redirect_to admin_agent_releases_path, notice: "Deleted #{version} and its installer"
    end
  end
end
