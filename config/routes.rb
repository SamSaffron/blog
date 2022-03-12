# frozen_string_literal: true

Blog::Engine.routes.draw do
  resources :secrets do
  end
  post "secrets/perform_show" => "secrets#perform_show"
  get "/" => "topics#index"
  get "posts" => "topics#index"
  get "sitemap.xml" => "topics#sitemap"
  get "about" => "blog#about"
  get "robots.txt" => "robots#index"
  get "*path" => "topics#permalink"
end
