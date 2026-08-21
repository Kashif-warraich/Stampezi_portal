ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: "Dashboard"

  content title: "Dashboard" do
    now = Time.current

    columns do
      column do
        panel "Licences" do
          licences = License.includes(:shop).to_a
          counts = licences.group_by { |licence| licence.status(now) }.transform_values(&:count)

          table_for %w[active grace expired] do
            column("Status") { |status| status }
            column("Shops") { |status| counts.fetch(status, 0) }
          end
        end
      end

      column do
        panel "Files waiting to be printed" do
          waiting = UploadSession.where(status: "Uploaded").count
          h2 waiting
          para "Uploaded but not yet claimed by a shop's desktop service."
        end
      end
    end

    panel "Recent uploads" do
      table_for UploadSession.includes(:shop).order(created_at: :desc).limit(10) do
        column("Shop") { |upload| link_to upload.shop.name, admin_shop_path(upload.shop) }
        column("File") { |upload| upload.file_name }
        column("Status") { |upload| status_tag upload.status }
        column("Received") { |upload| upload.created_at }
      end
    end
  end
end
