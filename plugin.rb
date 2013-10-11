# name: blog
# about: blog frontend for Discourse
# version: 0.1
# authors: Sam Saffron

gem "multi_xml","0.5.5"
gem "httparty", "0.12.0"
gem "rubyoverflow", "1.0.2"

::BLOG_HOST = Rails.env.development? ? "dev.samsaffron.com" : "samsaffron.com"
::BLOG_DISCOURSE = Rails.env.development? ? "l.discourse" : "discuss.samsaffron.com"

module ::Blog
  class Engine < ::Rails::Engine
    engine_name "blog"
    isolate_namespace Blog
  end
end

Rails.configuration.assets.precompile += ['LAB.js', 'blog.css']

after_initialize do

  load File.expand_path("../app/jobs/blog_update_twitter.rb", __FILE__)
  load File.expand_path("../app/jobs/blog_update_stackoverflow.rb", __FILE__)

  require_dependency "plugin/filter"

  Plugin::Filter.register(:after_post_cook) do |post, cooked|
    if post.post_number == 1 && post.topic && post.topic.archetype == "regular"
      split = cooked.split("<hr>")

      if split.length > 1
        post.topic.add_meta_data("summary",split[0])
        post.topic.save
        cooked = split[1..-1].join("<hr>")
      end
    end
    cooked
  end

  class BlogConstraint
    def matches?(request)
      request.host == BLOG_HOST
    end
  end

  class ::Topic
    before_save :blog_bake_summary
    before_save :ensure_permalink

    # see: https://github.com/rails/rails/issues/12497
    def add_meta_data(key,value)
      self.meta_data = (self.meta_data || {}).merge(key => value)
    end

    def ensure_permalink
      unless meta_data && meta_data["permalink"]
        add_meta_data("permalink", (Time.now.strftime "/archive/%Y/%m/%d/") + self.slug)
      end
    end

    def blog_bake_summary
      if meta_data && summary = meta_data["summary"]
        add_meta_data("cooked_summary", PrettyText.cook(summary))
      end
    end
  end

  Discourse::Application.routes.prepend do
    mount ::Blog::Engine, at: "/", constraints: BlogConstraint.new
  end
end
