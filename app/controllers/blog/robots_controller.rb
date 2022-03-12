# frozen_string_literal: true

module Blog
  class RobotsController < Blog::ApplicationController
    def index
      render plain: "User-Agent: *\nAllow: /"
    end
  end
end
