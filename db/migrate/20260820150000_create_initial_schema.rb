class CreateInitialSchema < ActiveRecord::Migration[8.1]
  def change
    # UUID primary keys, as in the Next.js portal: session ids appear in URLs and licence
    # QR codes are public, so sequential integers would be enumerable.
    create_table :users, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.timestamps
      t.index :email, unique: true
    end

    create_table :shops, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :licenses, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      # The permanent 10-digit identity of a shop: printed on the QR code, sent by the
      # desktop service, and the key for every licence operation. A string, not an integer:
      # 10 digits does not fit in 32 bits and it is an identifier, not a quantity.
      t.string :license_number, null: false
      t.references :shop, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.datetime :expires_at, null: false
      t.string :machine_fingerprint
      t.datetime :last_check_at
      t.datetime :last_reset_at
      t.timestamps
      t.index :license_number, unique: true
    end

    create_table :upload_sessions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :shop, type: :uuid, null: false, foreign_key: true
      t.string :status, null: false # Pending | Uploaded | Delivered | Expired
      t.string :file_name, null: false
      t.string :object_key, null: false
      t.datetime :delivered_at
      t.timestamps
      # Serves the desktop's poll: one shop's Uploaded rows, newest window first.
      t.index [ :shop_id, :status, :created_at ]
    end
  end
end
