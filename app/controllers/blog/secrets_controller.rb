# frozen_string_literal: true

module Blog
  class SecretsController < Blog::ApplicationController
    MAX_SECRET_LENGTH = 10_000
    SECRETS_PER_MINUTE = 30

    # Atomically read-and-delete a one-time secret so two concurrent
    # perform_show requests can't both return the value.
    FETCH_AND_DELETE = DiscourseRedis::EvalHelper.new <<~LUA
      local val = redis.call("get", KEYS[1])
      if val then
        redis.call("del", KEYS[1])
      end
      return val
    LUA

    before_action :rate_limit_create, only: :create

    def new
    end

    def create
      if (secret = params[:secret]) && (secret.length < MAX_SECRET_LENGTH)
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
      if (val = FETCH_AND_DELETE.eval(Discourse.redis, [redis_key(@token)]))
        render plain: val
      else
        render plain: "Sorry, secret info is gone!"
      end
    end

    protected

    def redis_key(token)
      "secret-#{token}"
    end

    private

    # A single anonymous writer could otherwise store up to 10 KB of secrets
    # (1-week TTL) without bound, exhausting Redis memory. Cap the rate per
    # signed-in user, or per IP when anonymous — same pattern as
    # EmailController.
    def rate_limit_create
      if current_user
        RateLimiter.new(current_user, "secrets_create", SECRETS_PER_MINUTE, 1.minute).performed!
      else
        RateLimiter.new(nil, "secrets_create_#{request.ip}", SECRETS_PER_MINUTE, 1.minute).performed!
      end
    end
  end
end
