# frozen_string_literal: true

# Monkey patch for Guardian to allow anonymous users to see topics with valid share tokens
# This is for blog draft review functionality
module GuardianPatch
  def can_see_topic?(topic, hide_deleted = true)
    if Thread.current[:share_token_value]
      token = TopicShareToken.find_by_token(Thread.current[:share_token_value])
      return true if token&.active? && token.topic_id == topic.id
    end

    super
  end
end
