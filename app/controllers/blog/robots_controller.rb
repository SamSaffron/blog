# frozen_string_literal: true

module Blog
  class RobotsController < Blog::ApplicationController
    def index
      render plain: <<~TEXT
        User-Agent: *
        Allow: /

        Sitemap: https://samsaffron.com/sitemap.xml
      TEXT
    end
  end
end
