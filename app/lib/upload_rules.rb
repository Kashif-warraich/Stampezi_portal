# Shared by the public upload page and the API, so the browser rejects what the server
# would reject anyway - same list, one place.
module UploadRules
  ALLOWED_EXTENSIONS = %w[pdf doc docx xls xlsx jpg jpeg png txt].freeze
  MAX_UPLOAD_BYTES = 50 * 1024 * 1024

  # "" when there is no extension, or nothing before the dot (".pdf" is a hidden file).
  def self.extension_of(file_name)
    dot = file_name.rindex(".")
    dot && dot > 0 ? file_name[(dot + 1)..].downcase : ""
  end

  def self.allowed?(file_name)
    ALLOWED_EXTENSIONS.include?(extension_of(file_name))
  end

  def self.max_megabytes
    MAX_UPLOAD_BYTES / (1024 * 1024)
  end
end
