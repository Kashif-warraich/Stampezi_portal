class AddPurgedAtToUploadSessions < ActiveRecord::Migration[8.1]
  def change
    # The row outlives the file: the admin's upload history is worth keeping, the bytes
    # are not. This is what stops the sweep offering the same key to R2 forever.
    add_column :upload_sessions, :purged_at, :datetime

    # The question every poll asks - "has this shop anything left to delete?" - and
    # nothing else. Partial, because purged rows are never looked at again and will
    # outnumber live ones by orders of magnitude.
    add_index :upload_sessions, %i[shop_id updated_at],
      where: "purged_at IS NULL", name: "index_upload_sessions_unpurged"
  end
end
