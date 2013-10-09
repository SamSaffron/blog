Blog::Engine.routes.draw do
  get "/" => "topics#index"
  get "posts" => "topics#index"
  get "about" => "blog#about"
  get "*path" => "topics#permalink"
end
