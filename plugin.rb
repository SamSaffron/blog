# frozen_string_literal: true

# name: blog
# about: blog frontend for Discourse
# version: 0.2
# authors: Sam Saffron

::BLOG_HOST = Rails.env.development? ? "dev.samsaffron.com" : "samsaffron.com"
::BLOG_DISCOURSE = Rails.env.development? ? "l.discourse" : "discuss.samsaffron.com"

module ::BlogAdditions
  class Engine < ::Rails::Engine
    engine_name "blog_additions"
    isolate_namespace BlogAdditions
  end
end

module ::Blog
  class Engine < ::Rails::Engine
    engine_name "blog"
    isolate_namespace Blog
  end

  def self.judge_gpt
    @judge_gpt ||= User.find(-100)
  end

  def self.corrupt_a_bot
    @corrupt_a_bot ||= User.find(-101)
  end

  def self.gpt_bot
    @gpt_bot ||= User.find(-102)
  end

  def self.open_ai_completion(messages, temperature: 1.0, top_p: 1.0, max_tokens: 700, model: nil)
    return if SiteSetting.blog_open_ai_api_key.blank?

    url = URI("https://api.openai.com/v1/chat/completions")
    headers = {
      "Content-Type": "application/json",
      Authorization: "Bearer #{SiteSetting.blog_open_ai_api_key}",
    }
    payload = {
      model: model || SiteSetting.blog_open_ai_model,
      messages: messages,
      max_tokens: max_tokens,
      top_p: top_p,
      temperature: temperature,
      stream: block_given?,
    }

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(url, headers)
    request.body = payload.to_json
    output = +""

    cancelled = false
    cancel = lambda { cancelled = true }

    http.request(request) do |response|
      if !block_given?
        body = response.read_body
        p body
        return JSON.parse(body)["choices"][0]["message"]["content"]
      end

      response.read_body do |chunk|
        if cancelled
          http.finish
          break
        end
        chunk
          .split("\n")
          .each do |line|
            data = line.split("data: ", 2)[1]
            next if data == "[DONE]"

            if data
              json = JSON.parse(data)
              partial = json["choices"][0].dig("delta", "content")
              if partial
                output << partial
                yield partial, cancel
              end
            end
          end
      end
    end
    output
  rescue IOError
    return output if cancelled
    raise
  end
end

Rails.configuration.assets.precompile += %w[LAB.js blog.css]

if Rails.env.development?
  require "middleware/enforce_hostname"
  Rails.configuration.middleware.insert_after Rack::MethodOverride, Middleware::EnforceHostname
end

after_initialize do
  SeedFu.fixture_paths << File.expand_path("../db/fixtures", __FILE__)

  add_to_serializer(:current_user, :gpt_bot_username) do
    group_ids = SiteSetting.blog_allowed_gpt_pms_groups.split("|").map(&:to_i)
    if groups.any? && object.groups.where(id: group_ids).exists?
      ::Blog.gpt_bot.username
    else
      nil
    end
  end

  # got to patch this class to allow more hostnames
  class ::Middleware::EnforceHostname
    def call(env)
      hostname = env[Rack::Request::HTTP_X_FORWARDED_HOST].presence || env[Rack::HTTP_HOST]

      env[Rack::Request::HTTP_X_FORWARDED_HOST] = nil

      if hostname == ::BLOG_HOST
        env[Rack::HTTP_HOST] = ::BLOG_HOST
      else
        env[Rack::HTTP_HOST] = ::BLOG_DISCOURSE
      end
      @app.call(env)
    end
  end

  load File.expand_path("../app/jobs/scheduled/blog_update_twitter.rb", __FILE__)
  load File.expand_path("../app/jobs/regular/corrupt_a_wish.rb", __FILE__)
  load File.expand_path("../lib/gpt_dispatcher.rb", __FILE__)

  require_dependency "plugin/filter"

  ::Blog.initialize_gpt_dispatcher(self)

  Plugin::Filter.register(:after_post_cook) do |post, cooked|
    if post.post_number == 1 && post.topic && post.topic.archetype == "regular"
      split = cooked.split(%r{<hr/?>})

      if split.length > 1
        post.topic.custom_fields["summary"] = split[0]
        post.topic.save unless post.topic.new_record?
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
      unless custom_fields["permalink"]
        custom_fields["permalink"] = (Time.now.strftime "/archive/%Y/%m/%d/") + self.slug
      end
    end

    def blog_bake_summary
      if summary = custom_fields["summary"]
        custom_fields["cooked_summary"] = PrettyText.cook(summary)
      end
    end
  end

  Discourse::Application.routes.prepend do
    mount ::Blog::Engine, at: "/", constraints: BlogConstraint.new
  end

  Discourse::Application.routes.append { mount ::BlogAdditions::Engine, at: "/blog" }
end
