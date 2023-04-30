# frozen_string_literal: true

module ::Jobs
  class HandleGptPm < ::Jobs::Base
    MAX_PROMPT_LENGTH = 3000

    def execute(args)
      post = Post.find_by(id: args["post_id"])
      gpt_answer(post) if post
      gpt_auto_title(post) if post
    rescue => e
      Discourse.warn_exception(e, message: "Failed to complete OpenAI request")
    end

    def gpt_auto_title(post)
      if post.post_number > 2 && post.topic.title == "New GPT Chat"
        DistributedMutex.synchronize("gpt-auto-title") do
          post.topic.reload
          return if post.topic.title != "New GPT Chat"
          messages = [{ role: "system", content: <<~TEXT }]
            Suggest a 5 word title for the following topic, do not quote the text I am using you as an API:

            #{post.topic.posts[1..-1].map(&:raw).join("\n\n")[0..MAX_PROMPT_LENGTH]}
          TEXT

          title = ::Blog.open_ai_completion(messages, temperature: 0.7, top_p: 0.9, max_tokens: 40)

          PostRevisor.new(post.topic.first_post, post.topic).revise!(
            Discourse.system_user,
            title: title,
          )
        end
      end
    end

    def gpt_answer(post)
      messages = [{ role: "system", content: <<~TEXT }]
          You are gpt-bot you answer questions and generate text.
          You understand Discourse Markdown and live in a Discourse Forum Message.
          You are provided you with context of previous discussions.
          TEXT

      prev_raws =
        post
          .topic
          .posts
          .includes(:user)
          .where("post_number <= ?", post.post_number)
          .order("post_number desc")
          .pluck(:raw, :username)

      reverse_messages = []

      length = 0
      prev_raws.each do |raw, username|
        length += raw.length
        break if length > MAX_PROMPT_LENGTH
        role = username == ::Blog.gpt_bot ? "system" : "user"

        reverse_messages << { role: role, content: raw }
      end

      messages += reverse_messages.reverse

      start = Time.now
      new_post = nil

      data = +""
      ::Blog.open_ai_completion(
        messages,
        temperature: 0.4,
        top_p: 0.9,
        max_tokens: 1000,
      ) do |partial, cancel|
        # nonsense do |partial, cancel|
        data << partial
        if (new_post && !Discourse.redis.get("gpt_cancel:#{new_post.id}"))
          cancel.call if cancel
        end
        next if Time.now - start < 0.5

        Discourse.redis.expire("gpt_cancel:#{new_post.id}", 60) if new_post

        start = Time.now

        if !new_post
          new_post =
            PostCreator.create!(
              ::Blog.gpt_bot,
              topic_id: post.topic_id,
              raw: data,
              skip_validations: true,
            )
          Discourse.redis.setex("gpt_cancel:#{new_post.id}", 60, 1)
        else
          new_post.update!(raw: data, cooked: PrettyText.cook(data))

          MessageBus.publish(
            "/fast-edit/#{post.topic_id}",
            { raw: data, post_id: new_post.id, post_number: new_post.post_number },
            user_ids: post.topic.allowed_user_ids,
          )
        end
      end

      MessageBus.publish(
        "/fast-edit/#{post.topic_id}",
        { done: true, post_id: new_post.id, post_number: new_post.post_number },
        user_ids: post.topic.allowed_user_ids,
      )

      new_post.revise(::Blog.gpt_bot, { raw: data }, skip_validations: true, skip_revision: true)
    end

    # for testing
    def nonsense
      cancelled = false
      cancel = lambda { cancelled = true }

      i = 1
      yield "this is some text\n\n```ruby\n"
      while i < 100
        break if cancelled

        i += 1
        sleep 0.2

        break if cancelled
        yield "def a#{i}; puts 1; end\n", cancel
      end
    end
  end
end
