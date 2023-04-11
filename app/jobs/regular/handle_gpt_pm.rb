# frozen_string_literal: true

module ::Jobs
  class HandleGptPm < ::Jobs::Base
    MAX_PROMPT_LENGTH = 3000

    def execute(args)
      post = Post.find_by(id: args["post_id"])
      gpt_answer(post) if post
    rescue => e
      Discourse.warn_exception(e, message: "Failed to complete OpenAI request")
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
      ) do |partial|
        #nonsense do |partial|
        data << partial
        next if Time.now - start < 0.5

        start = Time.now

        if !new_post
          new_post =
            PostCreator.create!(::Blog.gpt_bot, topic_id: post.topic_id, raw: data, validate: false)
        else
          post.update!(raw: data, cooked: PrettyText.cook(data))

          MessageBus.publish(
            "/fast-edit/#{post.topic_id}",
            { raw: data, post_id: new_post.id, post_number: new_post.post_number },
            user_ids: post.topic.allowed_user_ids,
          )
        end
      end

      new_post.revise(::Blog.gpt_bot, { raw: data }, skip_validations: true, skip_revision: true)
    end

    # for testing
    def nonsense
      i = 1
      while i < 50
        i += 1
        sleep 0.1
        yield "hello #{i}"
      end
    end
  end
end
