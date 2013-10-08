# name: blog
# about: blog frontend for Discourse
# version: 0.1
# authors: Sam Saffron

module ::Blog
  class Engine < ::Rails::Engine
    engine_name "blog"
    isolate_namespace Blog
  end
end

after_initialize do
  Discourse::Application.routes.prepend do
    mount ::Blog::Engine, at: "/"
  end
end
