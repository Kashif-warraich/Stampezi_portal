# ActiveAdmin ships Sass sources, so its stylesheet is compiled at build time. The gem's
# stylesheet directory goes on the load path so `@import "active_admin/base"` resolves.
Rails.application.config.dartsass.builds = { "active_admin.scss" => "active_admin.css" }

Rails.application.config.dartsass.build_options +=
  [ "--load-path=#{Gem::Specification.find_by_name('activeadmin').gem_dir}/app/assets/stylesheets" ]
