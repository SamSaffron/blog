# frozen_string_literal: true
module ::Blog
  def self.initialize_gpt_dispatcher(plugin)
    ::DiscourseEvent.on(:post_created) do |post|
      if SiteSetting.blog_corrupt_a_wish_topic_id.to_i == post.topic_id
        Jobs.enqueue(:corrupt_a_wish, post_id: post.id)
      end

      if post.topic.private_message? && post.user_id != ::Blog.gpt_bot.id
        if post.topic.topic_allowed_users.where(user_id: ::Blog.gpt_bot.id).exists?
          if post && SiteSetting.blog_allowed_gpt_pms_groups.present? &&
               post
                 .user
                 .groups
                 .where(
                   "groups.id in (?)",
                   SiteSetting.blog_allowed_gpt_pms_groups.split("|").map(&:to_i),
                 )
                 .exists?
            Jobs.enqueue(:handle_gpt_pm, post_id: post.id)
          end
        end
      end
    end
  end
end
