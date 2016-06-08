module Blog
  class UpdateTwitter < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      tweets = TwitterApi.user_timeline('samsaffron')

      tweets = tweets.map do |t|
        text = TwitterApi.prettify_tweet(t)
        text = ExcerptParser.get_excerpt(text, 400, {})
        {
          :text => text,
          :date => t["created_at"], :id => t["id"]
        }
      end
      Rails.cache.write("tweets", {:tweets => tweets}, :expires_in => 2.days)
    end

  end
end

