# name: blog
# about: blog frontend for Discourse
# version: 0.1
# authors: Sam Saffron

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

  require_dependency "plugin/filter"

  Plugin::Filter.register(:after_post_cook) do |post, cooked|
    if post.post_number == 1 && post.topic && post.topic.archetype == "regular"
      split = cooked.split("<hr>")

      # possibly defer this ... not sure
      post.topic.meta_data["summary"] = split[0]
      post.topic.save

      if split.length > 1
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

    def ensure_permalink
      meta_data["permalink"] ||= (Time.now.strftime "/archive/%Y/%m/%d/") + self.slug
    end

    def blog_bake_summary
      if summary = meta_data["summary"]
        meta_data["cooked_summary"] = PrettyText.cook(summary)
      end
    end
  end

  Discourse::Application.routes.prepend do
    mount ::Blog::Engine, at: "/", constraints: BlogConstraint.new
  end
end
