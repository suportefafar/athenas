Rails.application.routes.draw do
  root "home#index"
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest, defaults: { format: :json }
  resource :session, only: %i[new create destroy]
  get "invitation/:token", to: "invitations#edit", as: :invitation
  patch "invitation/:token", to: "invitations#update"
  get "search", to: "searches#index", as: :search
  resources :uploads, only: %i[new create]
  resources :lots, only: %i[show destroy] do
    member do
      get :preview
      get :download
    end
  end
  namespace :my do
    resources :uploads, only: :index
  end
  namespace :admin do
    resources :users, only: %i[index create] do
      post :invite, on: :member
    end
    resources :lots, only: :index
  end
end
