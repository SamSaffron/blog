# frozen_string_literal: true

class PatchDownloadToken
  TOKEN_TTL = 10.minutes.to_i

  def self.redis_key(token)
    "patch-download-token:#{token}"
  end

  def self.generate(patch_id)
    token = SecureRandom.urlsafe_base64(32)
    Discourse.redis.setex(redis_key(token), TOKEN_TTL, patch_id.to_s)
    token
  end

  def self.validate(token)
    return nil if token.blank?
    Discourse.redis.get(redis_key(token))&.to_i
  end
end
