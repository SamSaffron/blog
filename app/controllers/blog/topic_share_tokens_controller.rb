# frozen_string_literal: true

module Blog
  class TopicShareTokensController < ::ApplicationController
    before_action :ensure_logged_in
    before_action :ensure_admin
    before_action :find_topic

  def index
    @tokens = @topic.topic_share_tokens.active.includes(:user).order(created_at: :desc)
    render_serialized(@tokens, TopicShareTokenSerializer, topic: @topic)
  end

    def create
      @token = @topic.topic_share_tokens.build(user: current_user)

      if @token.save
        render json: {
                 token: @token.token,
                 expires_at: @token.expires_at,
                 share_url: topic_share_url(@topic, token: @token.token),
               }
      else
        render json: { errors: @token.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @token = @topic.topic_share_tokens.find(params[:id])
      @token.destroy
      render json: { success: true }
    end

    private

    def find_topic
      @topic = Topic.find(params[:topic_id])
    end

    def topic_share_url(topic, token:)
      "#{Discourse.base_url}/t/#{topic.slug}/#{topic.id}?token=#{token}"
    end
  end
end
