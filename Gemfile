source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Admin password hashing for the User model.
gem "bcrypt", "~> 3.1.7"

# The admin back office: one file per model gives full CRUD, filters and search.
# Installed with --skip-users, so it authenticates through the existing User model
# and session rather than pulling in Devise.
gem "activeadmin", "~> 3.5"
# ActiveAdmin ships Sass sources only. dartsass-rails compiles them and, unlike
# sassc-rails, does not drag Sprockets in alongside Rails 8's Propshaft.
gem "dartsass-rails"

# Server-side QR codes for the shop counter cards (the Next portal drew these in the
# browser with a canvas; a PNG endpoint is simpler and prints the same).
gem "rqrcode", "~> 3.0"

# R2 is S3-compatible: same SDK, different endpoint. Used only to presign PUT/GET URLs,
# so the file bytes never pass through this app.
gem "aws-sdk-s3", "~> 1.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Loads .env in every environment, so local and production differ by values only. Real
# environment variables win over the file, which does not exist on Render anyway.
gem "dotenv-rails"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end
