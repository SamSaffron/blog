# frozen_string_literal: true

class TopicShareTokenSerializer < ApplicationSerializer
  attributes :id, :token, :expires_at, :created_at, :share_url

  has_one :user, serializer: BasicUserSerializer, embed: :objects

  def share_url
    topic = object.topic
    "#{Discourse.base_url}/t/#{topic.slug}/#{topic.id}?token=#{object.token}"
  end
end
