ActiveAdmin.register AgentRelease do
  menu priority: 5, label: "Releases"

  # Releases are created by the build machine through the API. Editing one here would
  # desynchronise the row from the object sitting in R2.
  actions :index, :show

  filter :version
  filter :created_at

  scope :all, default: true
  scope("Installable") { |scope| scope.published.where(pruned_at: nil) }
  scope("Pruned")      { |scope| scope.where.not(pruned_at: nil) }

  index do
    column :version
    column("Shops on it") { |release| Shop.where(target_agent_version: release.version).count }
    column("State") do |release|
      if release.pruned?          then status_tag "pruned", class: :error
      elsif release.installable?  then status_tag "installable", class: :ok
      else                             status_tag "uploading", class: :warning
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
      table_for Shop.where(target_agent_version: resource.version).order(:name) do
        column("Shop") { |shop| link_to shop.name, admin_shop_path(shop) }
        column("Running") { |shop| shop.license&.agent_version || "not reported" }
        column("Last check-in") { |shop| shop.license&.last_check_at }
      end
    end
  end
end
