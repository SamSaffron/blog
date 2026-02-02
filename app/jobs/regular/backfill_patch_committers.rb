# frozen_string_literal: true

module ::Jobs
  class BackfillPatchCommitters < ::Jobs::Base
    sidekiq_options retry: false

    CONNECT_TIMEOUT = 10
    READ_TIMEOUT = 30

    def execute(args)
      # Process patches where github_id is NULL (not yet attempted)
      Patch
        .where(committer_github_id: nil)
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
      if SiteSetting.blog_github_api_token.present?
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
        # Mark as attempted with -1 to prevent re-fetching
        patch.update(committer_github_id: -1)
        return :not_found
      end

      data = JSON.parse(response.body)
      author = data.dig("commit", "author")
      github_user = data["author"]

      # Use -1 for github_id if not found, real ID otherwise
      patch.update(
        committer_email: author&.dig("email") || "",
        committer_name: author&.dig("name") || "",
        committer_github_username: github_user&.dig("login") || "",
        committer_github_id: github_user&.dig("id") || -1,
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
