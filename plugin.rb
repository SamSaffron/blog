# frozen_string_literal: true

# name: blog
# about: blog frontend for Discourse
# version: 0.2
# authors: Sam Saffron

::BLOG_HOST = Rails.env.development? ? "dev.samsaffron.com" : "samsaffron.com"
::BLOG_DISCOURSE =
  Rails.env.development? ? "l.discourse" : "discuss.samsaffron.com"

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

  def self.open_ai_completion(
    messages,
    temperature: 1.0,
    top_p: 1.0,
    max_tokens: 700,
    model: nil
  )
    return if SiteSetting.blog_open_ai_api_key.blank?

    url = URI("https://api.openai.com/v1/chat/completions")
    headers = {
      "Content-Type": "application/json",
      Authorization: "Bearer #{SiteSetting.blog_open_ai_api_key}"
    }
    payload = {
      model: model || SiteSetting.blog_open_ai_model,
      messages: messages,
      max_tokens: max_tokens,
      top_p: top_p,
      temperature: temperature,
      stream: block_given?
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

if Rails.env.development?
  require "middleware/enforce_hostname"
  Rails.configuration.middleware.insert_after Rack::MethodOverride,
  Middleware::EnforceHostname
end

after_initialize do
  SeedFu.fixture_paths << File.expand_path("../db/fixtures", __FILE__)

  # Load Guardian patch for anonymous topic access
  require_relative("lib/guardian_patch.rb")

  # Apply the Guardian patch
  Guardian.prepend(GuardianPatch)

  # Load topic share token model and controller
  require_relative("app/models/topic_share_token.rb")
  require_relative("app/controllers/blog/topic_share_tokens_controller.rb")
  require_relative("lib/topic_serializer_extension.rb")

  # Load Hot or Not models, controllers, and helpers
  require_relative("app/models/patch.rb")
  require_relative("app/models/patch_rating.rb")
  require_relative("app/models/patch_claim.rb")
  require_relative("app/models/patch_claim_log.rb")
  require_relative("app/controllers/hot_or_not_controller.rb")
  require_relative("app/controllers/hot_or_not/admin/patches_controller.rb")
  require_relative("app/helpers/hot_or_not_helper.rb")
  require_relative("lib/patch_download_token.rb")

  # Add association to Topic model
  reloadable_patch do |plugin|
    Topic.class_eval { has_many :topic_share_tokens, dependent: :destroy }
  end

  # Add patch_ratings and patch_claims associations to User model
  reloadable_patch do |plugin|
    User.class_eval do
      has_many :patch_ratings, dependent: :destroy
      has_many :patch_claims, dependent: :destroy
      has_many :patch_claim_logs, dependent: :destroy
    end
  end

  # Extend TopicViewSerializer
  reloadable_patch do
    ::TopicViewSerializer.prepend(Blog::TopicViewSerializerExtension)
  end

  # got to patch this class to allow more hostnames
  class ::Middleware::EnforceHostname
    def call(env)
      hostname =
        env[Rack::Request::HTTP_X_FORWARDED_HOST].presence ||
          env[Rack::HTTP_HOST]

      env[Rack::Request::HTTP_X_FORWARDED_HOST] = nil

      path = env["PATH_INFO"] || ""
      is_ai_share = path.start_with?("/discourse-ai/ai-bot/shared-ai")

      # In development, check for blog mode via query parameter or cookie
      is_blog_mode = false
      set_blog_cookie = nil
      clear_blog_cookie = false

      request = Rack::Request.new(env)

      # Capture share token for Guardian access via Thread.current
      if request.params["token"]
        Thread.current[:share_token_value] = request.params["token"]
      end

      if Rails.env.development?
        query_string = env["QUERY_STRING"] || ""

        # Check if user is explicitly setting blog mode via query param
        if query_string.include?("blog=1")
          is_blog_mode = true
          set_blog_cookie = true
        elsif query_string.include?("blog=0")
          is_blog_mode = false
          clear_blog_cookie = true
        else
          # Check cookie for persistent blog mode
          is_blog_mode = request.cookies["blog_mode"] == "1"
        end
      end

      if Rails.env.production?
        if (hostname == ::BLOG_HOST || is_blog_mode) && !is_ai_share
          env[Rack::HTTP_HOST] = ::BLOG_HOST
        else
          env[Rack::HTTP_HOST] = ::BLOG_DISCOURSE
        end
      end

      status, headers, body = @app.call(env)

      # Clean up Thread.current after request completes
      Thread.current[:share_token_value] = nil

      # Set or clear cookie in the response
      if set_blog_cookie
        Rack::Utils.set_cookie_header!(
          headers,
          "blog_mode",
          { value: "1", path: "/", expires: Time.now + 30.days }
        )
      elsif clear_blog_cookie
        Rack::Utils.delete_cookie_header!(headers, "blog_mode", { path: "/" })
      end

      [status, headers, body]
    end
  end

  require_relative("app/jobs/scheduled/blog_update_twitter.rb")
  require_relative("app/jobs/regular/corrupt_a_wish.rb")
  require_relative("app/jobs/regular/backfill_patch_committers.rb")
  require_relative("lib/gpt_dispatcher.rb")

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
      # In development, check for blog mode via query parameter or cookie
      if Rails.env.development?
        return true if request.params["blog"] == "1"
        return false if request.params["blog"] == "0"
        return true if request.cookies["blog_mode"] == "1"
      end

      request.host == BLOG_HOST
    end
  end

  class ::Topic
    before_save :blog_bake_summary
    before_save :ensure_permalink

    def ensure_permalink
      unless custom_fields["permalink"]
        custom_fields["permalink"] = (Time.now.strftime "/archive/%Y/%m/%d/") +
          self.slug
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

  Discourse::Application.routes.append do
    mount ::BlogAdditions::Engine, at: "/blog"

    # Topic share token routes
    resources :topics, only: [] do
      resources :topic_share_tokens,
                only: %i[index create destroy],
                controller: "blog/topic_share_tokens"
    end

    # Hot or Not routes (on main Discourse site)
    get "hot-or-not" => "hot_or_not#index"
    get "hot-or-not/list" => "hot_or_not#list"
    get "hot-or-not/leaderboard" => "hot_or_not#leaderboard"
    get "hot-or-not/stats" => "hot_or_not#stats"
    get "hot-or-not/my-patches" => "hot_or_not#my_patches"
    get "hot-or-not/users/:username" => "hot_or_not#user_profile"
    get "hot-or-not/by/:committer" => "hot_or_not#by_committer"
    get "hot-or-not/:id" => "hot_or_not#show"
    post "hot-or-not/:id/rate" => "hot_or_not#rate"
    get "hot-or-not/:id/download" => "hot_or_not#download"
    post "hot-or-not/:id/generate-download-token" => "hot_or_not#generate_download_token"
    get "hot-or-not/p/:token" => "hot_or_not#token_download"
    post "hot-or-not/:id/claim" => "hot_or_not#claim"
    delete "hot-or-not/:id/unclaim" => "hot_or_not#unclaim"
    post "hot-or-not/:id/resolve" => "hot_or_not#resolve"
    post "hot-or-not/:id/unresolve" => "hot_or_not#unresolve"

    scope path: "hot-or-not/admin", module: "hot_or_not/admin", as: "hot_or_not_admin" do
      resources :patches do
        collection do
          get :import
          post :perform_import
          post :recount_all
          post :backfill_committers
          post :add_voters_to_group
        end
        member { post :toggle_active }
      end
    end
  end
end
