Rails.application.routes.draw do
  ActiveAdmin.routes(self)
  root to: redirect("/admin/shops")

  # Public: the QR code points here with ?l=<licence>.
  get "/upload", to: "uploads#show", as: :upload

  get    "/admin/login",  to: "sessions#new",     as: :login
  post   "/admin/login",  to: "sessions#create"
  delete "/admin/logout", to: "sessions#destroy", as: :logout

  # /admin is ActiveAdmin (see app/admin/*.rb). The login routes above are declared
  # first so they win over the engine's own /admin paths.
  # Paths are fixed by the deployed .NET desktop service - do not rename them.
  namespace :api do
    resources :shops, only: %i[index create show update]

    post "license/check",         to: "licenses#check"
    post "license/extend",        to: "licenses#extend_license"
    post "license/reset-binding", to: "licenses#reset_binding"

    # Release publishing, driven from the build machine with the admin bearer token.
    post "agent-releases",             to: "agent_releases#create"
    post "agent-releases/:id/publish", to: "agent_releases#publish"

    post "upload-session",  to: "upload_sessions#create"
    post "upload-complete", to: "upload_completions#create"
    get  "pending-files",   to: "pending_files#index"
    post "files/:session_id/download-url", to: "download_urls#create"
    # Added after the deployed clients shipped, so an older desktop simply never calls it.
    post "files/:session_id/release",      to: "download_urls#release"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
