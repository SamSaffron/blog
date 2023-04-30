# frozen_string_literal: true

module ::Jobs
  class HandleGptPm < ::Jobs::Base
    def debug(str)
      puts str if Rails.env.development?
    end

    MAX_PROMPT_LENGTH = 5000
    GPT_INSTRUCTION_FIELD = "gpt_instruction"
    MAX_COMMANDS = 5

    def execute(args)
      post = Post.find_by(id: args["post_id"])
      gpt_answer(post) if post
      gpt_auto_title(post) if post
    rescue => e
      debug e.inspect
      Discourse.warn_exception(e, message: "Failed to complete OpenAI request")
    end

    def gpt_auto_title(post)
      if post.post_number > 2 && post.topic.title == "New GPT Chat"
        DistributedMutex.synchronize("gpt-auto-title") do
          post.topic.reload
          return if post.topic.title != "New GPT Chat"
          messages = [{ role: "system", content: <<~TEXT }]
            Suggest a 7 word title for the following topic, do not quote the text I am using you as an API:

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

    def gpt_answer(post, commands_run: 0)
      debug "GPT Answer was called command run: #{commands_run}"

      commands_run += 1

      return if commands_run > MAX_COMMANDS

      messages = [{ role: "system", content: <<~TEXT }]
        You are gpt-bot, you answer questions and generate text.
        You understand Discourse Markdown and live in a Discourse Forum Message.
        You are provided with the context of previous discussions.

        You can complete some tasks using multiple steps and have access to some special commands!

        !image DETAILED_IMAGE_DESCRIPTION
        !time RUBY_COMPATIBLE_TIMEZONE
        !userinfo
        !url_summary URL

        When issuing a command, always use the ! prefix. Never mix a user response with a command.
        The !image command can work on people, places, things, and more, as long as you can describe it.

        When generating !commands, ONLY EVER generate one command per post. Never add text after !commands.

        For multi-step tasks, follow the user’s preferred workflow by generating separate posts for each command.

        Keep in mind that the user may not see the !commands, the extra delay is fine.
      TEXT

      messages << {
        role: "user",
        content: "draw me a picture of Sauron and tell me 2 things about him",
      }
      messages << {
        role: "assistant",
        content:
          "!image Sauron: powerful, malevolent, shapeshifting entity; Dark Lord; creator of One Ring; seeks dominion; manifests as fiery, armored, one-eyed figure.",
      }
      messages << { role: "user", content: "![image](upload://wmRWpThF5acVqYYALKtuwW7TTtn.png)" }
      messages << {
        role: "assistant",
        content:
          "Here is an image of Sauron:\n![image](upload://wmRWpThF5acVqYYALKtuwW7TTtn.png)\n1. Sauron is a powerful, malevolent, shapeshifting entity.\n2. Sauron is a Dark Lord.",
      }

      prev_raws =
        post
          .topic
          .posts
          .includes(:user)
          .joins(
            "left join post_custom_fields pf on pf.post_id = posts.id and pf.name = '#{GPT_INSTRUCTION_FIELD}'",
          )
          .where("post_number <= ?", post.post_number)
          .order("post_number desc")
          .pluck(:raw, :username, :value, :post_type)

      reverse_messages = []

      length = 0
      prev_raws.each do |raw, username, value, post_type|
        length += raw.length
        break if length > MAX_PROMPT_LENGTH
        role = username == ::Blog.gpt_bot ? "assistant" : "user"

        if value.present?
          p "value is present"
          parsed =
            begin
              JSON.parse(value)
            rescue StandardError
              nil
            end
          p parsed

          if parsed
            parsed.reverse.each do |instruction|
              p instruction
              reverse_messages << { role: instruction["role"], content: instruction["content"] }
            end
          end
        end

        reverse_messages << { role: role, content: raw } if post_type != Post.types[:small_action]
      end

      messages += reverse_messages.reverse

      start = Time.now
      new_post = nil
      processing_command = false

      p messages

      data = +""
      ::Blog.open_ai_completion(
        messages,
        temperature: 0.4,
        top_p: 0.9,
        max_tokens: 1000,
      ) do |partial, cancel|
        # nonsense do |partial cancel|
        data << partial
        if (new_post && !Discourse.redis.get("gpt_cancel:#{new_post.id}"))
          cancel.call if cancel
        end
        next if Time.now - start < 0.5

        Discourse.redis.expire("gpt_cancel:#{new_post.id}", 60) if new_post

        debug "in loop #{data}"

        start = Time.now
        processing_command ||= data[0] == "!"

        if !new_post
          if !processing_command
            new_post =
              PostCreator.create!(
                ::Blog.gpt_bot,
                topic_id: post.topic_id,
                raw: data,
                skip_validations: true,
              )
            Discourse.redis.setex("gpt_cancel:#{new_post.id}", 60, 1)
          end
        else
          new_post.update!(raw: data, cooked: PrettyText.cook(data))

          MessageBus.publish(
            "/fast-edit/#{post.topic_id}",
            { raw: data, post_id: new_post.id, post_number: new_post.post_number },
            user_ids: post.topic.allowed_user_ids,
          )
        end
      end

      if new_post
        MessageBus.publish(
          "/fast-edit/#{post.topic_id}",
          { done: true, post_id: new_post.id, post_number: new_post.post_number },
          user_ids: post.topic.allowed_user_ids,
        )

        new_post.revise(::Blog.gpt_bot, { raw: data }, skip_validations: true, skip_revision: true)
      end

      process_command(post, data[1..-1].strip, commands_run: commands_run) if processing_command
    end

    def process_command(post, command, commands_run:)
      debug "COMMAND: #{command}"
      debug "POST: #{post.id}"

      if command.start_with?("image")
        description = command.split(" ", 2).last
        generate_image(post, description, commands_run: commands_run)
        return
      end

      if command.start_with?("time")
        timezone = command.split(" ").last
        time =
          begin
            Time.now.in_time_zone(timezone)
          rescue StandardError
            nil
          end
        time = Time.now if !time
        post.custom_fields[GPT_INSTRUCTION_FIELD] = [
          { role: "assistant", content: "!#{command}" },
          { role: "user", content: time.to_s },
        ].to_json
        post.save_custom_fields
        gpt_answer(post, commands_run: commands_run)
      end
    end

    def generate_image(post, description, commands_run:)
      debug "GENERATING IMAGE: #{description}"
      new_post =
        post.topic.add_moderator_post(
          ::Blog.gpt_bot,
          "Generating image: #{description}",
          post_type: Post.types[:small_action],
          action_code: "image_gen",
        )
      url = ::Blog.generate_dall_e_image(description)
      p "URL: #{url}"

      download =
        FileHelper.download(
          url,
          max_file_size: 10.megabytes,
          retain_on_max_file_size_exceeded: true,
          tmp_file_name: "discourse-hotlinked",
          follow_redirect: true,
          read_timeout: 15,
        )

      debug "DOWNLOADED"

      upload_creator = UploadCreator.new(download, "image.png")
      debug "CREATOR DONE"
      upload = upload_creator.create_for(::Blog.gpt_bot.id)
      debug "CREATED"

      new_post.custom_fields[GPT_INSTRUCTION_FIELD] = [
        { role: "assistant", content: "!image #{description}" },
        { role: "user", content: "![image](#{upload.short_url})" },
      ].to_json

      new_post.save_custom_fields
      gpt_answer(new_post, commands_run: commands_run)
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
