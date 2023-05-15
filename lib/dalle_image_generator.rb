# frozen_string_literal: true
module ::Blog
  class DalleImageGenerator
    def self.generate_url(prompt, size: "1024x1024")
      uri = URI.parse("https://api.openai.com/v1/images/generations")
      request = Net::HTTP::Post.new(uri)
      request.content_type = "application/json"
      request["Authorization"] = "Bearer #{SiteSetting.blog_open_ai_api_key}"
      request.body = { "prompt" => prompt, "n" => 1, "size" => size }.to_json

      req_options = { use_ssl: uri.scheme == "https" }

      response =
        Net::HTTP.start(uri.hostname, uri.port, req_options) { |http| http.request(request) }

      if response.code == "200"
        data = JSON.parse(response.body)
        data["data"][0]["url"]
      else
        # Handle error
        puts "Error: #{response.code}"
        raise "Error: could not generate image"
      end
    end

    def self.generate_image(description)
      url = generate_url(description)

      download =
        FileHelper.download(
          url,
          max_file_size: 10.megabytes,
          retain_on_max_file_size_exceeded: true,
          tmp_file_name: "discourse-hotlinked",
          follow_redirect: true,
          read_timeout: 15,
        )
      upload_creator = UploadCreator.new(download, "image.png")
      [upload_creator.create_for(::Blog.gpt_bot.id)]
    end
  end
end
