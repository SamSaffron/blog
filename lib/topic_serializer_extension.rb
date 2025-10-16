# frozen_string_literal: true

module Blog::TopicViewSerializerExtension
  extend ActiveSupport::Concern

  prepended { attributes :can_manage_share_tokens }

  def can_manage_share_tokens
    scope.is_admin?
  end
end
