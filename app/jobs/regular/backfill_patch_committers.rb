# frozen_string_literal: true

module ::Jobs
  class BackfillPatchCommitters < ::Jobs::Base
    sidekiq_options retry: false

    CONNECT_TIMEOUT = 10
    READ_TIMEOUT = 30

    def execute(args)
      # Only process patches that haven't been attempted yet
      Patch
        .where(committer_email: nil, committer_name: nil, committer_github_username: nil)
        .find_each do |patch|
          result = fetch_and_store_committer(patch)
          break if result == :rate_limited
        end
    end

    private

    def fetch_and_store_committer(patch)
      repo = patch.github_repo_path
      url = "https://api.github.com/repos/#{repo}/commits/#{patch.commit_hash}"

      headers = { "User-Agent" => "Discourse" }

      # Use GitHub token if configured
      if SiteSetting.respond_to?(:blog_github_api_token) &&
           SiteSetting.blog_github_api_token.present?
        headers["Authorization"] = "token #{SiteSetting.blog_github_api_token}"
      end

      response =
        Excon.get(url, headers: headers, connect_timeout: CONNECT_TIMEOUT, read_timeout: READ_TIMEOUT)

      # Handle rate limiting
      if response.status == 403 || response.status == 429
        Rails.logger.warn("BackfillPatchCommitters: Rate limited by GitHub API, stopping job")
        return :rate_limited
      end

      unless response.status == 200
        # Mark as attempted with empty string to prevent re-fetching
        patch.update(committer_email: "")
        return :not_found
      end

      data = JSON.parse(response.body)
      author = data.dig("commit", "author")
      github_user = data["author"]

      # Use empty string instead of nil to mark as attempted
      patch.update(
        committer_email: author&.dig("email") || "",
        committer_name: author&.dig("name") || "",
        committer_github_username: github_user&.dig("login") || "",
      )

      patch.match_committer_to_user!
      :success
    rescue StandardError => e
      Rails.logger.error(
        "BackfillPatchCommitters: Failed to fetch committer for patch #{patch.id}: #{e.message}",
      )
      :error
    end
  end
end
