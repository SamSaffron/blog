# frozen_string_literal: true

module Blog
  class TopicsController < Blog::ApplicationController
    def index
      respond_to do |format|
        format.html do
          @topics = visible_topics.by_newest
          render layout: "2col"
        end
        format.rss do
          @topics = topics_for_feed
          render
        end
        format.atom do
          @topics = topics_for_feed
          render
        end
      end
    end

    def show
    end

    def sitemap
      @topics = visible_topics.by_newest
      render content_type: "text/xml; charset=utf-8"
    end

    def permalink
      @topic =
        visible_topics.where(
          "id = (select topic_id from topic_custom_fields
                                      where name = 'permalink' and value = ?)",
          request.path,
        ).first
      if @topic
        @posts =
          Post
            .where(topic_id: @topic.id)
            .where(hidden: false)
            .by_post_number
            .includes(user: :user_profile)
            .to_a
        render action: "show"
      else
        render body: "404 - Blog post not found.".html_safe, status: 404
      end
    end

    protected

    def visible_topics
      list =
        Topic
          .secured
          .visible
          .listable_topics
          .where(
            "exists (select 1 from topic_custom_fields f where name = 'permalink' and topics.id = f.topic_id)",
          )
          .where("not exists(select c.topic_id from categories c where c.topic_id = topics.id)")
      excluded_categories = SiteSetting.blog_excluded_categories.split(",").map(&:to_i)
      if excluded_categories.present?
        list = list.where("topics.category_id not in (?)", excluded_categories)
      end
      list
    end

    def topics_for_feed
      visible_topics
        .by_newest
        .joins(:posts)
        .joins(:_custom_fields)
        .where("posts.post_number = 1")
        .where("topic_custom_fields.name = 'permalink'")
        .limit(10)
        .select("posts.cooked, topics.created_at, title, topic_custom_fields.value permalink")
    end
  end
end
