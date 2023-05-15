# frozen_string_literal: true
module ::Blog
  class StabilityImageGenerator
    def self.generate_image(
      engine_id: "stable-diffusion-xl-beta-v2-2-2",
      prompt:,
      cfg_scale: 7,
      height: 512,
      width: 512,
      clip_guidance_preset: "NONE",
      steps: 30,
      samples: 1
    )
      api_host = "https://api.stability.ai"
      api_key = SiteSetting.blog_stability_api_key

      uri = URI("#{api_host}/v1/generation/#{engine_id}/text-to-image")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request =
        Net::HTTP::Post.new(
          uri,
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "Authorization" => "Bearer #{api_key}",
        )

      request.body = {
        text_prompts: [{ text: prompt }],
        cfg_scale: 7,
        clip_guidance_preset: clip_guidance_preset,
        height: height,
        width: width,
        samples: samples,
        steps: steps,
      }.to_json

      response = http.request(request)

      raise "Non-200 response: #{response.body}" if response.code != "200"

      uploads = []

      data = JSON.parse(response.body)
      data["artifacts"].each_with_index do |image, i|
        f = Tempfile.new("v1_txt2img_#{i}.png")
        f.binmode
        f.write(Base64.decode64(image["base64"]))
        f.rewind
        uploads << UploadCreator.new(f, "image.png").create_for(::Blog.gpt_bot.id)
        f.unlink
      end

      uploads
    end
  end
end
