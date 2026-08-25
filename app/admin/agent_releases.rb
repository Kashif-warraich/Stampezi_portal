ActiveAdmin.register AgentRelease do
  menu priority: 5, label: "Releases"

  # No :new - creating a release means moving 230 MB, which the Upload page does with a
  # presigned PUT straight to R2.
  actions :index, :show, :edit, :update, :destroy
  permit_params :version, :notes

  filter :version
  filter :created_at

  scope :all, default: true
  scope("Installable") { |scope| scope.published.where(pruned_at: nil) }
  scope("Pruned")      { |scope| scope.where.not(pruned_at: nil) }

  # ActiveAdmin's stock Edit/Delete action items are <a data-method="delete"> links that
  # need jQuery-UJS to work. This app runs Propshaft with no Sprockets and no jQuery, so
  # that link quietly performed a GET and looked like it had done nothing. Replaced below
  # with a link and a form button, neither of which needs JavaScript.
  config.clear_action_items!

  action_item :upload, only: :index do
    link_to "Upload a release", upload_admin_agent_releases_path
  end

  action_item :edit, only: :show do
    link_to "Edit", edit_admin_agent_release_path(resource)
  end

  action_item :destroy, only: :show do
    render "admin/agent_releases/delete_button", release: resource
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
    column("") do |release|
      link_to("View", admin_agent_release_path(release), class: "member_link") +
        link_to("Edit", edit_admin_agent_release_path(release), class: "member_link") +
        render("admin/agent_releases/delete_button", release: release)
    end
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

    panel "Roll out" do
      render "admin/agent_releases/roll_out", release: resource
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs do
      f.input :version,
        hint: "Must match &lt;Version&gt; in the build this installer was made from. Renaming does not " \
              "change what the exe reports, so this is for correcting a mistyped version, not for " \
              "relabelling a build. The installer in R2 moves with it.".html_safe
      f.input :notes
    end
    f.actions
  end

  collection_action :upload, method: :get do
    # Renders app/views/admin/agent_releases/upload.html.erb.
  end

  member_action :roll_out, method: :post do
    release = resource
    ids = Array(params[:shop_ids]).reject(&:blank?)

    unless release.installable?
      return redirect_to admin_agent_release_path(release), alert: "#{release.version} is not installable."
    end

    Shop.where(id: ids).update_all(target_agent_version: release.version, updated_at: Time.current)
    # Unticked shops that were on this version are frozen where they are. Pointing them at
    # something older would be a rollback, and that has to be an explicit choice.
    Shop.where(target_agent_version: release.version).where.not(id: ids)
        .update_all(target_agent_version: nil, updated_at: Time.current)

    AppLog.info("agent_update.rollout", version: release.version, shops: ids.size)
    redirect_to admin_agent_release_path(release),
      notice: "#{ids.size} shop(s) now targeted at #{release.version}"
  end

  controller do
    # The object key embeds the version, so a rename has to move the installer too or the
    # row and the bytes stop describing each other.
    def update
      release = resource
      requested = params[:agent_release] || {}
      wanted = requested[:version].to_s.strip

      return super if wanted.blank? || wanted == release.version

      if release.targeted_by.any?
        return redirect_to edit_admin_agent_release_path(release),
          alert: "#{release.targeted_by.count} shop(s) are targeted at #{release.version}. Point them elsewhere before renaming it."
      end

      was = release.version
      old_key = release.object_key
      release.assign_attributes(
        version: wanted, object_key: R2.agent_release_key(wanted), notes: requested[:notes])

      unless release.valid?
        return redirect_to edit_admin_agent_release_path(release),
          alert: release.errors.full_messages.to_sentence
      end

      R2.move_object(old_key, release.object_key) unless release.pruned?
      release.save!
      AppLog.info("agent_release.renamed", from: was, to: wanted)

      redirect_to admin_agent_release_path(release), notice: "Renamed #{was} to #{wanted}"
    end

    # Deleting a release takes its installer out of R2 with it: the row alone is of no use,
    # and the object is exactly the storage pruning exists to reclaim.
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
