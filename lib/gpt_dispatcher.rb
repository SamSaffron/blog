# frozen_string_literal: true
module ::Blog
  def self.initialize_gpt_dispatcher(plugin)
    ::DiscourseEvent.on(:post_created) do |post|
      if SiteSetting.blog_corrupt_a_wish_topic_id.to_i == post.topic_id
        Jobs.enqueue(:corrupt_a_wish, post_id: post.id)
      end
    end
  end
end
