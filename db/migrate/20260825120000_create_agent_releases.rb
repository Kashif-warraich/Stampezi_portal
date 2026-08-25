class CreateAgentReleases < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_releases, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :version,    null: false
      t.string   :object_key, null: false
      # Computed on the build machine, not from R2: an end-to-end check that what a shop
      # downloads is the exe that was published, not something reassembled on the way.
      t.string   :sha256,     null: false
      t.bigint   :size_bytes
      t.text     :notes
      # Nil until the upload to R2 is confirmed - a half-uploaded release must never be
      # offered to a shop.
      t.datetime :published_at
      # Set when the R2 object is deleted to keep only the newest few. The row stays as
      # history, but the version can no longer be rolled back to.
      t.datetime :pruned_at
      t.timestamps

      t.index :version, unique: true
    end

    # What this shop should be running. Nil means "leave it alone", so a freshly published
    # release reaches nobody until someone says so - staged rollout by default.
    add_column :shops, :target_agent_version, :string

    # What it last reported running, for the fleet view.
    add_column :licenses, :agent_version, :string
  end
end
