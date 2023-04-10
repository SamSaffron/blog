# frozen_string_literal: true

module ::Jobs
  class HandleGptPm < ::Jobs::Base
    MAX_PROMPT_LENGTH = 2048

    def execute(args)
      post = Post.find_by(id: args["post_id"])
      gpt_answer(post) if post
    rescue => e
      Discourse.warn_exception(e, message: "Failed to complete OpenAI request")
    end

    def gpt_answer(post)
      messages = [{ role: "system", content: <<~TEXT }]
          You are gpt-bot you answer questions and generate text.
          You understand Markdown and live in a Discourse PM.
          I provide you with context of previous discussions.
          You do not prefix your answers with GPT_bot, .
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

        raw = <<~TEXT if role != "system"
            #{username}: #{raw}
          TEXT

        reverse_messages << { role: role, content: raw }
      end

      messages += reverse_messages.reverse

      start = Time.now
      new_post = nil

      data = +""
      ::Blog.open_ai_completion(messages, temperature: 0.4) do |partial|
        data << partial
        next if Time.now - start < 0.5

        start = Time.now

        if !new_post
          new_post =
            PostCreator.create!(::Blog.gpt_bot, topic_id: post.topic_id, raw: data, validate: false)
        else
          new_post.revise(
            ::Blog.gpt_bot,
            { raw: data },
            skip_validations: true,
            skip_revisions: true,
          )
        end
      end

      new_post.revise(::Blog.gpt_bot, { raw: data }, skip_validations: true, skip_revisions: true)
    end
  end
end
