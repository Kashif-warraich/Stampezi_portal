# Cloudflare R2 is S3-compatible: the same SDK against a different endpoint. Only URLs are
# signed here - the file bytes go straight from the customer's phone to R2 and back to the
# shop's desktop, never through this app.
module R2
  EXPIRES_IN = 5 * 60

  # Read at call time, never at boot: a missing key should fail the one request that needs
  # it, not stop the whole app from starting (Render builds without runtime secrets).
  def self.env(name)
    ENV[name].presence || raise("Missing environment variable #{name}")
  end

  def self.client
    Aws::S3::Client.new(
      region: "auto",
      endpoint: "https://#{env('R2_ACCOUNT_ID')}.r2.cloudflarestorage.com",
      access_key_id: env("R2_ACCESS_KEY_ID"),
      secret_access_key: env("R2_SECRET_ACCESS_KEY")
    )
  end

  def self.bucket = env("R2_BUCKET_NAME")

  # Strips path separators and anything else that could reshape the object key.
  def self.safe_name(file_name)
    file_name.gsub(/[^\w.\-]+/, "_").sub(/\A\.+/, "").presence || "upload"
  end

  def self.object_key_for(shop_id, session_id, file_name)
    "shops/#{shop_id}/incoming/#{session_id}/#{safe_name(file_name)}"
  end

  def self.presigned_put_url(shop_id, session_id, file_name)
    presigner.presigned_url(:put_object, bucket:, key: object_key_for(shop_id, session_id, file_name), expires_in: EXPIRES_IN)
  end

  def self.presigned_get_url(object_key)
    presigner.presigned_url(:get_object, bucket:, key: object_key, expires_in: EXPIRES_IN)
  end

  # Size in bytes, or nil when the object isn't there.
  def self.object_size(object_key)
    client.head_object(bucket:, key: object_key).content_length
  rescue Aws::S3::Errors::NotFound
    nil
  end

  def self.delete_object(object_key)
    client.delete_object(bucket:, key: object_key)
  end

  def self.presigner = Aws::S3::Presigner.new(client:)
end
