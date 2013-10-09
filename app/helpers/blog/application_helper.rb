module Blog
  module ApplicationHelper
    def permalink(topic)
      topic.meta_data["permalink"]
    end

    def user_link(user)
      name = user.name || user.username
      if user.website.present?
        link_to name, user.website
      else
        name
      end.html_safe
    end

    def age(date)
      FreedomPatches::Rails4.time_ago_in_words(date, false, scope: :'datetime.distance_in_words_verbose')
    end
  end
end
