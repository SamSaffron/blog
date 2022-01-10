# frozen_string_literal: true

module Blog
  class SecretsController < Blog::ApplicationController
    def new
    end

    def create
      if (secret = params[:secret]) && (secret.length < 10000)
        hex = SecureRandom.hex
        Discourse.redis.setex(redis_key(hex), 1.week, secret)
        render plain: "https://samsaffron.com/secrets/#{hex}"
      end
    end

    def show
      @token = params[:id]
      if !Discourse.redis.get redis_key(@token)
        @expired = true
      end
    end

    def perform_show
      @token = params[:id]
      if val = Discourse.redis.get(key = redis_key(@token))
        Discourse.redis.del(key)
        render plain: val
      else
        render plain: "Sorry, secret info is gone!"
      end
    end

    protected

    def redis_key(token)
      "secret-#{token}"
    end

  end
end
