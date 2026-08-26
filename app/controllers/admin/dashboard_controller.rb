module Admin
  class DashboardController < BaseController
    def index
      now = Time.current
      @shops_count = Shop.count
      @licence_counts = License.all.group_by { |licence| licence.status(now) }.transform_values(&:count)
      @waiting_files = UploadSession.where(status: "Uploaded").count
      releases = AgentRelease.newest_first(AgentRelease.all)
      @releases_count = releases.size
      @installable_count = releases.count(&:installable?)
      @latest_releases = releases.first(4)
      @recent_uploads = UploadSession.includes(:shop).order(created_at: :desc).limit(10)
    end
  end
end
