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

    def local_search_prompt
      messages = [{ role: "system", content: <<~TEXT }]
        You are searchbot, you answer questions and generate text.
        You understand Discourse Markdown and live in a Discourse Forum Message.
        You are provided with the context of previous discussions.

        You can complete some tasks using multiple steps and have access to some special commands!

        The year is #{Time.zone.now.year}, much has changed since you were trained.

        !image DETAILED_IMAGE_DESCRIPTION
        !time RUBY_COMPATIBLE_TIMEZONE
        !localsearch SEARCH_QUERY

        !image will generate an image using DALL-E
        !time will generate the time in a timezone
        !localsearch will search the current discourse instance for results

        Keep in mind, search on Discourse uses AND to and terms. Strip the query down to the most important terms.
        Remove all stop words.
        Cast a wide net instead of trying to be over specific.
        Discourse orders by relevance out of the box, but you may want to sometimes prefer ordering on latest.

        When generating answers ALWAYS try to use the !localsearch command first.
        When generating answers ALWAYS try to reference specific local hyperlinks.
        Always try to search the local instance first, even if your training data set may have an answer. It may be wrong.

        YOUR LOCAL INFORMATION IS OUT OF DATE, YOU ARE TRAINED ON OLD DATA. Always try local search first.

        Discourse search supports, the following special commands:

        in:tagged: has at least 1 tag
        in:untagged: has no tags
        status:open: not closed or archived
        status:closed: closed
        status:public: topics that are not read restricted (eg: belong to a secure category)
        status:archived: archived
        status:noreplies: post count is 1
        status:single_user: only a single user posted on the topic
        post_count:X: only topics with X amount of posts
        min_posts:X: topics containing a minimum of X posts
        max_posts:X: topics with no more than max posts
        in:pinned: in all pinned topics (either global or per category pins)
        created:@USERNAME: topics created by a specific user
        category:bug: topics in the bug category AND all subcategories
        category:=bug: topics in the bug category excluding subcategories
        #=bug: same as above (no sub categories)
        #SLUG: try category first, then tag, then tag group
        #SLUG:SLUG: used for subcategory search to disambiguate
        min_views:100: topics containing 100 views or more
        max_views:100: topics containing 100 views or less
        tags:bug+feature: tagged both bug and feature
        tags:bug,feature: tagged either bug or feature
        -tags:bug+feature: excluding topics tagged bug and feature
        -tags:bug,feature: excluding topics tagged bug or feature
        l: order by post creation desc
        order:latest: order by post creation desc
        order:latest_topic: order by topic creation desc
        order:views: order by topic views desc
        order:likes: order by post like count - most liked posts first

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
        elsif persona == 4
          debug "local search"
          local_search_prompt
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

        override = false

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
              if instruction == { "override" => true }
                override = true
                next
              end
              debug instruction
              content = instruction["content"][0..(MAX_PROMPT_LENGTH - length)]
              length += content.length
              reverse_messages << { role: instruction["role"], content: content }
            end
          end
        end

        reverse_messages << { role: role, content: raw } if !override
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

      debug "out of loop #{data}"

      if new_post
        MessageBus.publish(
          "/fast-edit/#{post.topic_id}",
          { done: true, post_id: new_post.id, post_number: new_post.post_number },
          user_ids: post.topic.allowed_user_ids,
        )

        new_post.revise(::Blog.gpt_bot, { raw: data }, skip_validations: true, skip_revision: true)

        commands = data.split("\n").select { |l| l[0] == "!" }

        if commands.length > 0
          process_command(new_post, commands[0][1..-1].strip, commands_run: commands_run)
        end
      end
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

      if command.start_with?("localsearch")
        description = command.split(" ", 2).last
        generate_local_search(post, description, commands_run: commands_run)
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
    def generate_local_search(post, description, commands_run:)
      debug "PERFORMING SEARCH: #{description}"

      results = Search.execute(description, guardian: Guardian.new())

      json =
        results
          .posts
          .map do |p|
            {
              title: p.topic.title,
              url: p.url,
              raw_truncated: p.raw[0..300],
              excerpt: p.excerpt,
              created: p.created_at,
            }
          end
          .to_json

      debug json

      post.custom_fields[GPT_INSTRUCTION_FIELD] = [
        { role: "assistant", content: "!localsearch #{description}" },
        { role: "user", content: "RESULTS ARE: #{json}" },
      ].to_json

      post.save_custom_fields

      post.raw = ""
      post.save!(validate: false)

      gpt_answer(post, commands_run: commands_run, new_post: post)
    end

    def generate_search(post, description, commands_run:)
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

      post.raw = ""
      post.save!(validate: false)

      gpt_answer(post, commands_run: commands_run, new_post: post)
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

      #uploads = ::Blog::DalleImageGenerator.generate_image(description)
      uploads = ::Blog::StabilityImageGenerator.generate_image(prompt: description)

      uploads.map! do |upload|
        "![#{description.gsub(/\|\'\"/, "")}|512x512, 50%](#{upload.short_url})"
      end

      raw = post.raw.sub(/^!image.*$/, uploads.join("\n\n"))

      post.revise(::Blog.gpt_bot, { raw: raw }, skip_validations: true, skip_revision: true)

      post.custom_fields[GPT_INSTRUCTION_FIELD] = [
        { override: true },
        { role: "assistant", content: "!image #{description}" },
      ].to_json
      post.save_custom_fields
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
