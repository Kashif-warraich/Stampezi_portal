Rails.application.routes.draw do
  root to: redirect("/admin")

  # Public: the QR code points here with ?l=<licence>.
  get "/upload", to: "uploads#show", as: :upload

  get    "/admin/login",  to: "sessions#new",     as: :login
  post   "/admin/login",  to: "sessions#create"
  delete "/admin/logout", to: "sessions#destroy", as: :logout
  # The sidebar's Sign out is a plain link (no JavaScript is loaded), so it performs a GET.
  # sessions#destroy only resets the session, so the worst a forged GET can do is sign
  # someone out.
  get "/admin/logout", to: "sessions#destroy"

  # The admin back office (app/controllers/admin). The login routes above are declared
  # first so they win over /admin/:id-style routes.
  namespace :admin do
    root to: "dashboard#index"

    resources :shops do
      member do
        get  :qr
        post :extend_license
        post :reset_binding
      end
    end

    # No :new/:create - creating a release means moving 230 MB, which the upload page does
    # with a presigned PUT straight to R2.
    resources :agent_releases, only: %i[index show edit update destroy] do
      get  :upload,   on: :collection
      post :roll_out, on: :member
    end

    resources :users, except: %i[show]
  end

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
