Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # --- Auth (OmniAuth GitHub, identity only) ---
  post "/auth/github" => "sessions#passthru", as: :github_auth      # form posts here; OmniAuth intercepts
  get  "/auth/github/callback" => "sessions#create"
  match "/auth/failure" => "sessions#failure", via: %i[get post]
  delete "/logout" => "sessions#destroy", as: :logout

  # --- GitHub App install + webhooks ---
  get  "/install" => "installations#new", as: :install            # redirect to GitHub App install
  get  "/install/callback" => "installations#callback", as: :install_callback
  post "/webhooks/github" => "webhooks#github", as: :github_webhook

  # --- Contributor wallet linking ---
  resource :wallet, only: %i[show create], controller: :wallets

  # --- Maintainer funding flow ---
  resources :bounties, only: %i[index show new create]

  # --- Discovery + trust ---
  get "/directory" => "directory#index", as: :directory
  get "/trust" => "trust#index", as: :trust

  # Dashboard / landing
  get "/dashboard" => "dashboard#show", as: :dashboard
  root "home#index"
end
