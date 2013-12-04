module Blog
  class TopicsController < Blog::ApplicationController
    def index

      respond_to do |format|
        format.html {
          @topics = visible_topics.by_newest
          render :layout => "2col"
        }
        format.rss {
          @topics = topics_for_feed
          render
        }
        format.atom {
          @topics = topics_for_feed
          render
        }
      end
    end

    def show
    end

    def permalink
      @topic = visible_topics.where("meta_data @> ?", "permalink => #{request.path}").first
      if @topic
        @posts = Post.where(topic_id: @topic.id)
                     .where(hidden: false)
                     .by_post_number
                     .includes(:user)
                     .to_a
        render :action => "show"
      else
        render :text => "<p>404 - Page not found.</p>", :status => 404
      end
    end

    protected

    def visible_topics
      Topic.secured.visible.listable_topics
        .where("meta_data ? 'permalink' AND topics.title not like 'Category definition%'")
    end

    def topics_for_feed
      visible_topics
        .by_newest
        .joins(:posts)
        .where("posts.post_number = 1")
        .limit(10)
        .select("meta_data, posts.cooked, topics.created_at, title")
    end

  end
end
