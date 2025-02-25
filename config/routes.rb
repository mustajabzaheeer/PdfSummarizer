Rails.application.routes.draw do
  devise_for :users

  authenticated :user do
    root to: "home#index", as: :authenticated_root
    post "generate_summaries", to: "home#generate_summaries"
    get "download_summaries", to: "home#download_summaries"
  end

  unauthenticated do
    devise_scope :user do
      root to: "devise/sessions#new", as: :unauthenticated_root
    end
  end
end
