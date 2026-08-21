# The one admin account. Plain text here, bcrypt in the database - has_secure_password
# hashes it on assignment, so the password never reaches Postgres in the clear.
#
#   bin/rails db:seed        (idempotent: an existing admin is left alone)
EMAIL = ENV.fetch("ADMIN_EMAIL", "admin@stampezi.it")
PASSWORD = ENV.fetch("ADMIN_PASSWORD")  # no default: a known admin password in production is a way in

if User.exists?
  puts "users already present, nothing seeded"
else
  User.create!(email: EMAIL, password: PASSWORD)
  puts "seeded #{EMAIL}"
end
