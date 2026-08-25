# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_25_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_releases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "notes"
    t.string "object_key", null: false
    t.datetime "pruned_at"
    t.datetime "published_at"
    t.string "sha256", null: false
    t.bigint "size_bytes"
    t.datetime "updated_at", null: false
    t.string "version", null: false
    t.index ["version"], name: "index_agent_releases_on_version", unique: true
  end

  create_table "licenses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "agent_version"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_check_at"
    t.datetime "last_reset_at"
    t.string "license_number", null: false
    t.string "machine_fingerprint"
    t.uuid "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["license_number"], name: "index_licenses_on_license_number", unique: true
    t.index ["shop_id"], name: "index_licenses_on_shop_id", unique: true
  end

  create_table "shops", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "target_agent_version"
    t.datetime "updated_at", null: false
  end

  create_table "upload_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "file_name", null: false
    t.string "object_key", null: false
    t.uuid "shop_id", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "status", "created_at"], name: "index_upload_sessions_on_shop_id_and_status_and_created_at"
    t.index ["shop_id"], name: "index_upload_sessions_on_shop_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "licenses", "shops"
  add_foreign_key "upload_sessions", "shops"
end
