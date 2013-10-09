require_dependency 'discourse'
require_dependency 'archetype'

module Blog
  class ApplicationController < ActionController::Base
    include CurrentUser
    layout "2col"

    def show_sidebar
      true
    end
  end
end
