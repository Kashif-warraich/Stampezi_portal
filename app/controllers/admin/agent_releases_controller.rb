module Admin
  # No :new/:create here - creating a release means moving 230 MB, which the Upload page
  # does with a presigned PUT straight to R2 (see the upload action and its view).
  class AgentReleasesController < BaseController
    FILTERS = %w[all installable pruned].freeze

    before_action :set_release, only: %i[show edit update destroy roll_out]

    def index
      @q = params[:q].to_s.strip
      @filter = FILTERS.include?(params[:filter]) ? params[:filter] : "all"
      @total = AgentRelease.count

      scope = case @filter
              when "installable" then AgentRelease.installable
              when "pruned"      then AgentRelease.where.not(pruned_at: nil)
              else                    AgentRelease.all
              end
      scope = scope.where("version LIKE ?", "%#{AgentRelease.sanitize_sql_like(@q)}%") if @q.present?
      @releases = AgentRelease.newest_first(scope)

      # Two counts per release, and two queries for the whole page rather than two per row.
      #
      # Running is what each shop last told us it was executing, so it moves on its own as
      # licence checks come in. Targeted is what an operator asked for and only moves when
      # someone clicks Apply. During a rollout the gap between them IS the progress.
      @running  = License.where.not(agent_version: nil).group(:agent_version).count
      @targeted = Shop.where.not(target_agent_version: nil).group(:target_agent_version).count
    end

    def show
      @shops = Shop.includes(:license).order(:name)
    end

    def edit; end

    # The object key embeds the version, so a rename has to move the installer too or the
    # row and the bytes stop describing each other.
    def update
      wanted = params.dig(:agent_release, :version).to_s.strip

      if wanted.blank? || wanted == @release.version
        @release.update!(notes: params.dig(:agent_release, :notes))
        return redirect_to admin_agent_release_path(@release), notice: "Saved"
      end

      if @release.targeted_by.any?
        return redirect_to edit_admin_agent_release_path(@release),
          alert: "#{@release.targeted_by.count} shop(s) are targeted at #{@release.version}. Point them elsewhere before renaming it."
      end

      was = @release.version
      old_key = @release.object_key
      @release.assign_attributes(
        version: wanted, object_key: R2.agent_release_key(wanted), notes: params.dig(:agent_release, :notes))

      unless @release.valid?
        return redirect_to edit_admin_agent_release_path(@release),
          alert: @release.errors.full_messages.to_sentence
      end

      R2.move_object(old_key, @release.object_key) unless @release.pruned?
      @release.save!
      AppLog.info("agent_release.renamed", from: was, to: wanted)

      redirect_to admin_agent_release_path(@release), notice: "Renamed #{was} to #{wanted}"
    end

    # Deleting a release takes its installer out of R2 with it: the row alone is of no use,
    # and the object is exactly the storage pruning exists to reclaim.
    def destroy
      if @release.targeted_by.any?
        names = @release.targeted_by.order(:name).limit(5).pluck(:name).join(", ")
        return redirect_to admin_agent_release_path(@release),
          alert: "#{@release.targeted_by.count} shop(s) are still targeted at #{@release.version} (#{names}). Point them elsewhere first."
      end

      version = @release.version
      @release.delete_object!
      @release.destroy!
      AppLog.info("agent_release.deleted", version:)

      redirect_to admin_agent_releases_path, notice: "Deleted #{version} and its installer"
    end

    def upload
      # Renders app/views/admin/agent_releases/upload.html.erb.
    end

    def roll_out
      ids = Array(params[:shop_ids]).reject(&:blank?)

      unless @release.installable?
        return redirect_to admin_agent_release_path(@release), alert: "#{@release.version} is not installable."
      end

      Shop.where(id: ids).update_all(target_agent_version: @release.version, updated_at: Time.current)
      # Unticked shops that were on this version are frozen where they are. Pointing them at
      # something older would be a rollback, and that has to be an explicit choice.
      Shop.where(target_agent_version: @release.version).where.not(id: ids)
          .update_all(target_agent_version: nil, updated_at: Time.current)

      AppLog.info("agent_update.rollout", version: @release.version, shops: ids.size)
      redirect_to admin_agent_release_path(@release),
        notice: "#{ids.size} shop(s) now targeted at #{@release.version}"
    end

    private

    def set_release
      @release = AgentRelease.find(params[:id])
    end
  end
end
