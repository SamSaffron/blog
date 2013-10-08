module Blog
  class PostsController < ActionController::Base
    include CurrentUser
    layout "2col"

    def index
      @posts = Topic.all
    end

    def show_sidebar
      true
    end
  end
end
