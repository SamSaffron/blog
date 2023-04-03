# frozen_string_literal: true

module Jobs
  class CorruptAWish < ::Jobs::Base
    sidekiq_options retry: false

    def judge_gpt
      @judge_gpt ||= User.find(-100)
    end

    def gpt_bot
      @gpt_bot ||= User.find(-101)
    end

    def execute(args)
      begin
        post = Post.find_by(id: args["post_id"])
        return if post.post_type != Post.types[:regular]
        judge(post)
        return if post.user_id == gpt_bot.id
        corrupt(post) if post
      rescue => e
        p e
      end
    end

    def open_ai_completion(messages, temperature: 1.0)
      return if SiteSetting.blog_open_ai_api_key.blank?

      url = URI("https://api.openai.com/v1/chat/completions")
      headers = {
        "Content-Type": "application/json",
        Authorization: "Bearer #{SiteSetting.blog_open_ai_api_key}",
      }
      payload = {
        model: SiteSetting.blog_open_ai_model,
        messages: messages,
        max_tokens: 700,
        temperature: temperature,
      }

      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(url, headers)
      request.body = payload.to_json
      response = http.request(request)
      JSON.parse(response.body)["choices"][0]["message"]["content"].strip
    end

    def judge(post)
      previous_post =
        Post
          .where(topic_id: post.topic_id)
          .where("post_number < ?", post.post_number)
          .where(post_type: Post.types[:regular])
          .order("created_at desc")
          .first
      return if previous_post.blank?

      match = previous_post.raw.match(/i wish.*\Z/mi)
      return if !match

      wish = match[0]

      formatted = "wish: #{wish}}\n please judge: #{post.raw}"
      messages = [
        { role: "system", content: <<~TEXT },
            You are judge-gpt you judge the quality of the wishes and corruptions.
            Your judgements are from 0 (not creative at all) to 10 (extremely creative and extremely on point).
            You never reply with "previous corruption mentioned, you always judge no matter what.
            Corruptions need to be plausible, not just taked on rediculous ideas.
            You are not a stickler, sometimes people have combination wishes and that is OK, judge them as 1.
            You only judge and only return wish and corruption scores. You never explain why.
          TEXT
        { role: "user", content: <<~TEXT },
            wish:
            I wish that I could possess the ability to breathe underwater and explore the depths of the oceans.

            please judge:
            Granted! You can now communicate with animals effectively, but with the catch that you’re forced to speak in a high-pitched, baby voice whenever you’re translating their language. This makes people around you think you’re insane or weird, and they can’t take you seriously. You end up alienated from everyone around you and lonely due to your unique ability.

I wish that I could possess the ability to breathe underwater and explore the depths of the oceans.
          TEXT
        { role: "assistant", content: <<~TEXT },
          wish: 5
          corruption: 6
        TEXT
        { role: "user", content: <<~TEXT },
          I don't like this game I dont care

          I wish for carp
        TEXT
        { role: "assistant", content: <<~TEXT },
          wish: 3
          corruption: 0
        TEXT
        { role: "user", content: formatted },
      ]
      begin
        new_post = open_ai_completion(messages, temperature: 0.1)

        wish_score = new_post.match(/wish: (\d+)/)[1].to_f
        corruption_score = new_post.match(/corruption: (\d+)/)[1].to_f

        # we start with a wish only
        if post.post_number > 2
          GptRating.create!(
            post_id: post.id,
            wish_score: wish_score,
            corruption_score: corruption_score,
          )
        end

        post.topic.add_moderator_post(
          judge_gpt,
          new_post,
          post_type: Post.types[:small_action],
          action_code: "judge_gpt",
        )

        update_leaderboard(post.topic)
      rescue => e
        Discourse.warn_exception(e, message: "Failed to complete OpenAI request")
      end
    end

    def update_leaderboard(topic)
      first_post = topic.posts.where(post_number: 1).first
      return if first_post.blank?

      rows = DB.query(<<~SQL, topic_id: topic.id)
        select
          sum(wish_score) as wish_score,
          sum(corruption_score) as corruption_score,
          count(*) as count,
          u.id,
          u.username
        from gpt_ratings gr
        join posts p on p.id = gr.post_id
        join users u on u.id = p.user_id
        where p.topic_id = :topic_id AND p.deleted_at IS NULL
        group by u.id, u.username
        order by sum(corruption_score) / count(*) desc
      SQL

      table = +<<~MD
        Name | Wish Score | Corruption Score | Attempts
        | --- | --- | --- | --- |
      MD

      rows.each { |row| table << <<~MD }
        #{row.username} | #{(row.wish_score / row.count).round(2)} | #{(row.corruption_score / row.count).round(2)} | #{row.count}
      MD

      new_raw = first_post.raw.sub(%r{\[wrap\=leaderboard\].*\[/wrap\]}mi, table)

      first_post.revise(judge_gpt, { raw: new_raw }, skip_validations: true)
    end

    def corrupt(post)
      previous_wishes = +""
      Post
        .where("post_number < ?", post.post_number)
        .where(post_type: Post.types[:regular])
        .order("created_at desc")
        .limit(30)
        .pluck(:raw)
        .each do |raw|
          match = raw.match(/i wish.*\Z/mi)
          previous_wishes << "#{raw}\n" if match
        end

      messages = [
        { role: "system", content: <<~TEXT },
            You are corrupt-a-wish bot, you will always reply with a wish corruption, followed by a wish of your own!
            Your wishes are extremely creative, your corruptions would scale a 10 on the creativity and on-point scale.
            You avoid making wishes that are too similar to previous ones.
            You are fun, funny, and creative. Your ideas always make people smile and the corruptions make sense.
            Sometimes you reply with a 1 paragraph wish grant, sometimes it takes 3 paragraphs to be awesome.
            People love you!
            You avoid previous interactions and try to always offer a new spin.

            previous wishes and corruptions are:
            #{previous_wishes[0..2000]}
          TEXT
        { role: "user", content: "I wish I could fly" },
        { role: "assistant", content: <<~TEXT },
            Granted! You now have the ability to fly, but only when you're completely covered in syrup. The sticky substance attracts all sorts of insects and small animals, causing chaos and discomfort wherever you go. Additionally, the process of cleaning off the syrup after each flight is laborious and time-consuming, leaving you with a bittersweet feeling about your newfound power.

            I wish that every time I snap my fingers, I can instantly learn and master a new artistic skill or talent.
            TEXT
        { role: "user", content: post.raw },
      ]

      begin
        new_post = open_ai_completion(messages, temperature: 1.0)
        PostCreator.create!(gpt_bot, topic_id: post.topic_id, raw: new_post)
      rescue => e
        Discourse.warn_exception(e, message: "Failed to complete OpenAI request")
      end
    end
  end
end
