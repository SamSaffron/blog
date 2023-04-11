# frozen_string_literal: true

module BlogAdditions
  class GptController < ApplicationController
    def cancel_generation
      post = Post.find(params[:post_id])
      guardian.ensure_can_see!(post)

      Discourse.redis.del("gpt_cancel:#{post.id}")
    end
  end
end
