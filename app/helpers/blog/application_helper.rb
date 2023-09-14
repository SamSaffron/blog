# frozen_string_literal: true

require_dependency "twitter_api"

module Blog
  module ApplicationHelper
    def permalink(topic)
      topic.custom_fields["permalink"]
    end

    def user_link(user)
      name = user.name || user.username
      if user.user_profile.website.present?
        link_to name, user.user_profile.website
      else
        name
      end.html_safe
    end

    def age(date)
      AgeWords.time_ago_in_words(date, false, scope: :'datetime.distance_in_words_verbose')
    end

    def latest_answers
      cached = Rails.cache.read("so_answers")
      cached ? cached[:answers] : []
    rescue
      []
    end

    def latest_tweets
      cached = Rails.cache.read("tweets")
      cached ? cached[:tweets][0..5] : []
    rescue
      []
    end

  end
end
