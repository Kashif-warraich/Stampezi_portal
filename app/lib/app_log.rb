# Structured logging: one JSON object per line, so a collector can filter by event or
# shop_id instead of grepping prose. Same event names as the Next.js portal emitted.
module AppLog
  REDACTED = %w[password presignedPutUrl downloadUrl token authorization].freeze

  def self.info(event, fields = {}) = emit(:info, event, fields)
  def self.warn(event, fields = {}) = emit(:warn, event, fields)
  def self.error(event, fields = {}) = emit(:error, event, fields)

  def self.emit(level, event, fields)
    # Presigned URLs and passwords are credentials; never let them reach a log file.
    safe = fields.each_with_object({}) do |(key, value), acc|
      acc[key] = REDACTED.include?(key.to_s) ? "[redacted]" : value
    end

    Rails.logger.public_send(level, { ts: Time.current.utc.iso8601(3), level:, event: }.merge(safe).to_json)
  end
  private_class_method :emit
end
