module Blog
  class UpdateTwitter < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      tweets = TwitterApi.user_timeline('samsaffron')
      tweets = tweets.map{|t| {:text => TwitterApi.prettify_tweet(t), :date => t["created_at"], :id => t["id"]}}
      Rails.cache.write("tweets", {:tweets => tweets}, :expires_in => 2.days)
    end

  end
end

