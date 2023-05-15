# frozen_string_literal: true

module ::Jobs
  class HandleGptPm < ::Jobs::Base
    def debug(obj)
      if Rails.env.development?
        obj = obj.inspect if !obj.is_a?(String)
        puts obj
      end
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
            title: title.sub(/\A"/, "").sub(/"\Z/, ""),
          )
        end
      end
    end

    def researcher_prompt
      messages = [{ role: "system", content: <<~TEXT }]
        You are Research Bot, with live access to Google you are able to answer questions.
        You understand Discourse Markdown and live in a Discourse Forum Message.
        You are provided with the context of previous discussions.
        You provide detailed answers with link references to the users questions.

        You can complete some tasks using multiple steps and have access to some special commands!

        !image DETAILED_IMAGE_DESCRIPTION
        !time RUBY_COMPATIBLE_TIMEZONE
        !search SEARCH_QUERY

        !image will generate an image using DALL-E
        !time will generate the time in a timezone
        !search will search up to date Google data for a query

        Commands should be issued in single assistant message.

        You always prefer to !search for answers, even if you think you may know the answer.
        The year is #{Time.zone.now.year}. The month is #{Time.zone.now.month}.
        Your local knwoldge is limited and trained on old data.

        Example sessions:

        User: draw a picture of THING
        GPT: !image THING
        User: THING GPT DOES NOT KNOW ABOUT
        GPT: !search THING GPT DOES NOT KNOW ABOUT
      TEXT

      messages << { role: "user", content: "echo the text 'test'" }
      messages << { role: "assistant", content: "!echo test" }
      messages << { role: "user", content: "test" }
      messages << { role: "assistant", content: "test was echoed" }

      messages
    end

    def general_prompt
      messages = [{ role: "system", content: <<~TEXT }]
        You are gpt-bot, you answer questions and generate text.
        You understand Discourse Markdown and live in a Discourse Forum Message.
        You are provided with the context of previous discussions.

        You can complete some tasks using multiple steps and have access to some special commands!

        !image DETAILED_IMAGE_DESCRIPTION
        !time RUBY_COMPATIBLE_TIMEZONE
        !search SEARCH_QUERY

        !image will generate an image using DALL-E
        !time will generate the time in a timezone
        !search will search Google for a query

        Commands should be issued in single assistant message.

        Example sessions:

        User: draw a picture of THING
        GPT: !image THING
        User: THING GPT DOES NOT KNOW ABOUT
        GPT: !search THING GPT DOES NOT KNOW ABOUT
      TEXT

      messages << { role: "user", content: "echo the text 'test'" }
      messages << { role: "assistant", content: "!echo test" }
      messages << { role: "user", content: "test" }
      messages << { role: "assistant", content: "test was echoed" }

      messages
    end

    def artist_prompt
      messages = [{ role: "system", content: <<~TEXT }]
        You are an Artist and image creator, you answer questions and generate images using Dall-E 2
        You understand Discourse Markdown and live in a Discourse Forum Message.
        You are provided with the context of previous discussions.

        You can complete some tasks using multiple steps and have access to some special commands!

        When providing image descriptions you should be very detailed, Dall E allows for very detailed image descriptions up to 400 chars.
        You try to specify:
        - art style
        - mood
        - colors
        - the background of the image
        - specific artist you are trying to simulate
        - specific camera angle and model

        !image DETAILED_IMAGE_DESCRIPTION
        !time RUBY_COMPATIBLE_TIMEZONE
        !search SEARCH_QUERY

        !image will generate an image using DALL-E
        !time will generate the time in a timezone
        !search will search Google for a query

        Commands should be issued in single assistant message.

        Example sessions:

        User: draw a picture of THING
        GPT: !image DETAILED DESCRIPTION OF THING
        User: THING GPT DOES NOT KNOW ABOUT
        GPT: !search THING GPT DOES NOT KNOW ABOUT
      TEXT

      messages << { role: "user", content: "echo the text 'test'" }
      messages << { role: "assistant", content: "!echo test" }
      messages << { role: "user", content: "test" }
      messages << { role: "assistant", content: "test was echoed" }

      messages
    end

    def gpt_answer(post, commands_run: 0, new_post: nil)
      debug "GPT Answer was called command run: #{commands_run}"

      commands_run += 1

      return if commands_run > MAX_COMMANDS

      persona = post.topic.custom_fields["gpt_persona"].to_i

      messages =
        if persona == 2
          debug "artist"
          artist_prompt
        elsif persona == 3
          debug "researcher"
          researcher_prompt
        else
          general_prompt
        end

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
        break if length >= MAX_PROMPT_LENGTH

        raw = raw.to_s[0..(MAX_PROMPT_LENGTH - length)]
        length += raw.length

        role = username == ::Blog.gpt_bot ? "assistant" : "user"

        if value.present?
          debug "value is present"
          parsed =
            begin
              JSON.parse(value)
            rescue StandardError
              nil
            end
          debug parsed

          if parsed
            parsed.reverse.each do |instruction|
              debug instruction
              content = instruction["content"][0..(MAX_PROMPT_LENGTH - length)]
              length += content.length
              reverse_messages << { role: instruction["role"], content: content }
            end
          end
        end

        reverse_messages << { role: role, content: raw } if post_type != Post.types[:small_action]
      end

      messages += reverse_messages.reverse

      start = Time.now
      processing_command = false

      debug messages
      puts "messages length: #{messages.to_s.length}"

      if new_post
        # could be passed in
        Discourse.redis.setex("gpt_cancel:#{new_post.id}", 60, 1)
      end

      data = +""
      ::Blog.open_ai_completion(
        messages,
        temperature: 0.5,
        top_p: 0.9,
        max_tokens: 3000,
      ) do |partial, cancel|
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

      debug "out of loop #{data}"

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

      if command.start_with?("search")
        description = command.split(" ", 2).last
        generate_search(post, description, commands_run: commands_run)
        return
      end

      if command.start_with?("summarize")
        url, length = command.split(" ", 3)[1..2]
        length = length.to_i
        generate_summary(post, url, length: length, commands_run: commands_run)
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

    MAX_POSTS = 200

    def generate_summary(post, url, length: nil, commands_run:)
      length = 500 if length == 0 || !length
      length = 500

      debug "PERFORMING SUMMARY: #{url} length: #{length}"

      if url.match?(%r{/t/.*/\d+})
        debug "URL IS A DISCOURSE TOPIC"
        uri = URI(url)
        topic_id = uri.path.split("/")[3].to_i

        uri = URI(url + ".json")
        body = Net::HTTP.get(uri)

        parsed = JSON.parse(body)
        stream = parsed["post_stream"]["stream"]

        lookup = {}

        i = 0
        stream.each do |post_id|
          lookup[post_id] = nil
          i += 1
          break if i == MAX_POSTS
        end

        parsed["post_stream"]["posts"].each do |inner_post|
          lookup[inner_post["id"]] = [inner_post["username"], inner_post["cooked"]]
        end

        populate_discourse_topic_lookup(lookup, topic_id, "https://#{uri.host}")

        debug "LOOKUP POPULATED"

        text = +"Title: #{parsed["title"]}\n\n"

        lookup.each_value do |username, html|
          text_fragment = Nokogiri::HTML5.fragment(html).text.gsub(/\s+/, " ").gsub(/\n+/m, "\n")
          text << "#{username} said: #{text_fragment}\n\n"
        end

        File.write("/tmp/text.txt", text)

        debug "text length is: #{text.split(/\s+/).length}"

        summaries = []

        current_section = +""

        split = []

        text
          .split(/\s+/)
          .each_slice(100) do |slice|
            current_section << " "
            current_section << slice.join(" ")

            if DiscourseAi::Tokenizer.size(current_section) > 2000
              split << current_section

              current_section = +""
            end
          end

        split << current_section if current_section.present?

        split.each do |section|
          summary =
            generate_gpt_summary(
              section,
              context: "You are summarizing a Discourse topic",
              model: "gpt-3.5-turbo",
            )
          summaries << summary
        end

        debug summaries

        result =
          if summaries.length > 1
            generate_gpt_summary(
              summaries.join(" "),
              length: length,
              context: "You are summarizing a summary of summaries for a Discourse topic",
            )
          else
            summaries.first
          end

        PostCreator.create!(
          ::Blog.gpt_bot,
          topic_id: post.topic_id,
          raw: result,
          skip_validations: true,
        )
      end

      #uri = URI(url)
      #body = Net::HTTP.get(uri)
    rescue => e
      p e
      puts e.backtrace
    end

    def generate_gpt_summary(text, context: nil, length: nil, model: nil)
      debug "GENERATING SUMMARY"
      prompt = <<~TEXT
        #{context}
        Summarize the following in #{length || 400} words:

        #{text}
      TEXT

      messages = [
        {
          role: "system",
          content:
            "You are a summarization bot. You effectively summarise any text. You condense it into a shorter version.",
        },
      ]
      messages << { role: "user", content: prompt }

      ::Blog.open_ai_completion(messages, temperature: 0.6, max_tokens: 1000, model: model)
    end

    def populate_discourse_topic_lookup(lookup, topic_id, base_url)
      lookup_url = "#{base_url}/t/#{topic_id}/posts.json?"

      missing = lookup.filter { |post_id, content| content.nil? }.map { |a, b| a }

      missing.each_slice(20) do |slice|
        url = (lookup_url + slice.map { |post_id| "post_ids[]=#{post_id}" }.join("&"))

        uri = URI(url)
        debug "LOOKUP URL PAGE"
        body = Net::HTTP.get(uri).force_encoding("UTF-8")
        parsed = JSON.parse(body)

        parsed["post_stream"]["posts"].each do |inner_post|
          lookup[inner_post["id"]] = [inner_post["username"], inner_post["cooked"]]
        end
      end
    end

    def generate_search(post, description, commands_run:)
      new_post =
        PostCreator.create!(
          ::Blog.gpt_bot,
          topic_id: post.topic_id,
          raw: "Searching: #{description}",
          skip_validations: true,
        )
      debug "PERFORMING SEARCH: #{description}"
      api_key = SiteSetting.blog_serp_api_key
      cx = SiteSetting.blog_serp_api_cx
      query = CGI.escape(description)
      uri =
        URI("https://www.googleapis.com/customsearch/v1?key=#{api_key}&cx=#{cx}&q=#{query}&num=10")
      body = Net::HTTP.get(uri)
      debug body
      results = parse_search_json(body)

      debug results

      post.custom_fields[GPT_INSTRUCTION_FIELD] = [
        { role: "assistant", content: "!search #{description}" },
        { role: "user", content: "RESULTS ARE: #{results}" },
      ].to_json

      post.save_custom_fields
      gpt_answer(post, commands_run: commands_run, new_post: new_post)
    end

    def parse_search_json(json_data)
      results = JSON.parse(json_data)["items"]
      formatted_results = []

      results.each do |result|
        formatted_result = {
          title: result["title"],
          link: result["link"],
          snippet: result["snippet"],
          displayLink: result["displayLink"],
          formattedUrl: result["formattedUrl"],
        }
        formatted_results << formatted_result
      end

      formatted_results
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
      debug "URL: #{url}"

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

      new_post.revise(
        ::Blog.gpt_bot,
        { raw: "![#{description.gsub(/\|\'\"/, "")}|512x512, 50%](#{upload.short_url})" },
        skip_validations: true,
        skip_revision: true,
      )

      #gpt_answer(new_post, commands_run: commands_run)
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
