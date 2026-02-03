# frozen_string_literal: true

SUPPORTED_EXPORT_VERSIONS = [1].freeze unless defined?(SUPPORTED_EXPORT_VERSIONS)

namespace :blog do
  namespace :patch_triage do
    desc "Export all patch triage data (patches, ratings, claims, logs) to JSON"
    task :export, [:file_path] => [:environment] do |_, args|
      file_path =
        args[:file_path] || "tmp/patch_triage_export_#{Time.current.strftime("%Y%m%d_%H%M%S")}.json"

      puts "Exporting patch triage data to #{file_path}..."

      # Collect all user IDs referenced across all tables
      user_ids = Set.new

      Patch.find_each do |patch|
        user_ids << patch.committer_user_id if patch.committer_user_id
        user_ids << patch.resolved_by_id if patch.resolved_by_id
      end

      PatchRating.distinct.pluck(:user_id).each { |id| user_ids << id }
      PatchClaim.distinct.pluck(:user_id).each { |id| user_ids << id }
      PatchClaimLog.distinct.pluck(:user_id).each { |id| user_ids << id }

      puts "  Found #{user_ids.size} unique users to export"

      # Build user reference map
      users_data = {}
      user_id_to_ref = {}

      User
        .where(id: user_ids.to_a)
        .find_each do |user|
          ref = "user_#{user.id}"
          user_id_to_ref[user.id] = ref
          users_data[ref] = { email: user.email, username: user.username, name: user.name }
        end

      puts "  Loaded #{users_data.size} users"

      # Export patches and build commit_hash lookup in single pass
      patches_data = []
      patch_commit_hashes = {}
      Patch.find_each do |patch|
        patch_commit_hashes[patch.id] = patch.commit_hash
        patches_data << {
          commit_hash: patch.commit_hash,
          title: patch.title,
          summary: patch.summary,
          markdown_content: patch.markdown_content,
          diff_content: patch.diff_content,
          issue_type: patch.issue_type,
          audit_date: patch.audit_date&.iso8601,
          repository: patch.repository,
          useful_count: patch.useful_count,
          not_useful_count: patch.not_useful_count,
          active: patch.active,
          committer_email: patch.committer_email,
          committer_name: patch.committer_name,
          committer_github_username: patch.committer_github_username,
          committer_github_id: patch.committer_github_id,
          committer_user_ref: user_id_to_ref[patch.committer_user_id],
          resolved_at: patch.resolved_at&.iso8601(6),
          resolved_by_ref: user_id_to_ref[patch.resolved_by_id],
          resolution_status: patch.resolution_status,
          resolution_notes: patch.resolution_notes,
          resolution_changeset_url: patch.resolution_changeset_url,
          created_at: patch.created_at.iso8601(6),
          updated_at: patch.updated_at.iso8601(6),
        }
      end

      puts "  Exported #{patches_data.size} patches"

      # Export ratings
      ratings_data = []
      PatchRating.find_each do |rating|
        ratings_data << {
          patch_commit_hash: patch_commit_hashes[rating.patch_id],
          user_ref: user_id_to_ref[rating.user_id],
          is_useful: rating.is_useful,
          created_at: rating.created_at.iso8601(6),
          updated_at: rating.updated_at.iso8601(6),
        }
      end

      puts "  Exported #{ratings_data.size} ratings"

      # Export claims
      claims_data = []
      PatchClaim.find_each do |claim|
        claims_data << {
          patch_commit_hash: patch_commit_hashes[claim.patch_id],
          user_ref: user_id_to_ref[claim.user_id],
          notes: claim.notes,
          created_at: claim.created_at.iso8601(6),
          updated_at: claim.updated_at.iso8601(6),
        }
      end

      puts "  Exported #{claims_data.size} claims"

      # Export claim logs
      claim_logs_data = []
      PatchClaimLog.find_each do |log|
        claim_logs_data << {
          patch_commit_hash: patch_commit_hashes[log.patch_id],
          user_ref: user_id_to_ref[log.user_id],
          action: log.action,
          notes: log.notes,
          created_at: log.created_at.iso8601(6),
          updated_at: log.updated_at.iso8601(6),
        }
      end

      puts "  Exported #{claim_logs_data.size} claim logs"

      # Build final export structure
      export_data = {
        exported_at: Time.current.iso8601,
        version: 1,
        counts: {
          patches: patches_data.size,
          patch_ratings: ratings_data.size,
          patch_claims: claims_data.size,
          patch_claim_logs: claim_logs_data.size,
        },
        users: users_data,
        patches: patches_data,
        patch_ratings: ratings_data,
        patch_claims: claims_data,
        patch_claim_logs: claim_logs_data,
      }

      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, JSON.pretty_generate(export_data))

      puts ""
      puts "Export complete!"
      puts "  File: #{file_path}"
      puts "  Size: #{File.size(file_path)} bytes"
    end

    desc "Import patch triage data from JSON (re-runnable)"
    task :import, [:file_path] => [:environment] do |_, args|
      file_path = args[:file_path]

      unless file_path.present? && File.exist?(file_path)
        puts "ERROR: File path required and must exist"
        puts "Usage: rake blog:patch_triage:import[path/to/export.json]"
        exit 1
      end

      puts "Importing patch triage data from #{file_path}..."

      data = JSON.parse(File.read(file_path))

      version = data["version"]
      if SUPPORTED_EXPORT_VERSIONS.exclude?(version)
        puts "ERROR: Unsupported export version: #{version}"
        puts "Supported versions: #{SUPPORTED_EXPORT_VERSIONS.join(", ")}"
        exit 1
      end

      puts "  Export date: #{data["exported_at"]}"
      puts "  Version: #{version}"
      puts "  Expected counts:"
      puts "    - Patches: #{data["counts"]["patches"]}"
      puts "    - Ratings: #{data["counts"]["patch_ratings"]}"
      puts "    - Claims: #{data["counts"]["patch_claims"]}"
      puts "    - Claim logs: #{data["counts"]["patch_claim_logs"]}"
      puts ""

      # Phase 1: Resolve user references
      puts "Phase 1: Resolving users..."

      user_ref_to_id = {}
      users_created = 0
      users_matched = 0

      data["users"].each do |ref, user_data|
        user = find_or_create_import_user(user_data)

        if user.previously_new_record?
          users_created += 1
        else
          users_matched += 1
        end

        user_ref_to_id[ref] = user.id
      end

      puts "  Users matched: #{users_matched}"
      puts "  Users created (staged): #{users_created}"
      puts ""

      # Phase 2: Import patches
      puts "Phase 2: Importing patches..."

      patches_created = 0
      patches_updated = 0
      patch_errors = []

      commit_hash_to_patch_id = {}

      data["patches"].each_with_index do |patch_data, idx|
        print "\r  Processing patch #{idx + 1}/#{data["patches"].size}..."
        $stdout.flush

        begin
          patch = Patch.find_or_initialize_by(commit_hash: patch_data["commit_hash"])
          is_new = patch.new_record?

          patch.assign_attributes(
            title: patch_data["title"],
            summary: patch_data["summary"],
            markdown_content: patch_data["markdown_content"],
            diff_content: patch_data["diff_content"],
            issue_type: patch_data["issue_type"],
            audit_date: patch_data["audit_date"] ? Date.parse(patch_data["audit_date"]) : nil,
            repository: patch_data["repository"],
            useful_count: patch_data["useful_count"] || 0,
            not_useful_count: patch_data["not_useful_count"] || 0,
            active: patch_data["active"].nil? ? true : patch_data["active"],
            committer_email: patch_data["committer_email"],
            committer_name: patch_data["committer_name"],
            committer_github_username: patch_data["committer_github_username"],
            committer_github_id: patch_data["committer_github_id"],
            committer_user_id: user_ref_to_id[patch_data["committer_user_ref"]],
            resolved_at: patch_data["resolved_at"] ? Time.parse(patch_data["resolved_at"]) : nil,
            resolved_by_id: user_ref_to_id[patch_data["resolved_by_ref"]],
            resolution_status: patch_data["resolution_status"],
            resolution_notes: patch_data["resolution_notes"],
            resolution_changeset_url: patch_data["resolution_changeset_url"],
          )

          patch.save!

          # Preserve original timestamps
          patch.update_columns(
            created_at: Time.zone.parse(patch_data["created_at"]),
            updated_at: Time.zone.parse(patch_data["updated_at"]),
          )

          commit_hash_to_patch_id[patch_data["commit_hash"]] = patch.id

          is_new ? patches_created += 1 : patches_updated += 1
        rescue => e
          patch_errors << { commit_hash: patch_data["commit_hash"], error: e.message }
        end
      end

      puts "\r  Patches created: #{patches_created}                    "
      puts "  Patches updated: #{patches_updated}"
      puts "  Errors: #{patch_errors.size}"
      patch_errors.each { |err| puts "    - #{err[:commit_hash]}: #{err[:error]}" }
      puts ""

      # Phase 3: Import ratings (skip callbacks, recount at end)
      puts "Phase 3: Importing ratings..."

      ratings_created = 0
      ratings_updated = 0
      ratings_skipped = 0

      data["patch_ratings"].each_with_index do |rating_data, idx|
        print "\r  Processing rating #{idx + 1}/#{data["patch_ratings"].size}..."
        $stdout.flush

        patch_id = commit_hash_to_patch_id[rating_data["patch_commit_hash"]]
        user_id = user_ref_to_id[rating_data["user_ref"]]

        unless patch_id && user_id
          ratings_skipped += 1
          next
        end

        existing = PatchRating.find_by(patch_id: patch_id, user_id: user_id)

        created_at = Time.zone.parse(rating_data["created_at"])
        updated_at = Time.zone.parse(rating_data["updated_at"])

        if existing
          existing.update_columns(
            is_useful: rating_data["is_useful"],
            created_at: created_at,
            updated_at: updated_at,
          )
          ratings_updated += 1
        else
          PatchRating.insert(
            {
              patch_id: patch_id,
              user_id: user_id,
              is_useful: rating_data["is_useful"],
              created_at: created_at,
              updated_at: updated_at,
            },
          )
          ratings_created += 1
        end
      end

      puts "\r  Ratings created: #{ratings_created}                    "
      puts "  Ratings updated: #{ratings_updated}"
      puts "  Ratings skipped (missing refs): #{ratings_skipped}"
      puts ""

      # Phase 4: Import claims
      puts "Phase 4: Importing claims..."

      claims_created = 0
      claims_updated = 0
      claims_skipped = 0

      data["patch_claims"].each_with_index do |claim_data, idx|
        print "\r  Processing claim #{idx + 1}/#{data["patch_claims"].size}..."
        $stdout.flush

        patch_id = commit_hash_to_patch_id[claim_data["patch_commit_hash"]]
        user_id = user_ref_to_id[claim_data["user_ref"]]

        unless patch_id && user_id
          claims_skipped += 1
          next
        end

        claim = PatchClaim.find_or_initialize_by(patch_id: patch_id, user_id: user_id)
        is_new = claim.new_record?

        claim.assign_attributes(notes: claim_data["notes"])
        claim.save!

        # Preserve original timestamps
        claim.update_columns(
          created_at: Time.zone.parse(claim_data["created_at"]),
          updated_at: Time.zone.parse(claim_data["updated_at"]),
        )

        is_new ? claims_created += 1 : claims_updated += 1
      end

      puts "\r  Claims created: #{claims_created}                    "
      puts "  Claims updated: #{claims_updated}"
      puts "  Claims skipped (missing refs): #{claims_skipped}"
      puts ""

      # Phase 5: Import claim logs (skip duplicates)
      puts "Phase 5: Importing claim logs..."

      logs_created = 0
      logs_skipped = 0

      data["patch_claim_logs"].each_with_index do |log_data, idx|
        print "\r  Processing log #{idx + 1}/#{data["patch_claim_logs"].size}..."
        $stdout.flush

        patch_id = commit_hash_to_patch_id[log_data["patch_commit_hash"]]
        user_id = user_ref_to_id[log_data["user_ref"]]

        unless patch_id && user_id
          logs_skipped += 1
          next
        end

        created_at = Time.zone.parse(log_data["created_at"])
        updated_at = Time.zone.parse(log_data["updated_at"])

        # Exact match on all fields to detect duplicates
        existing =
          PatchClaimLog.exists?(
            patch_id: patch_id,
            user_id: user_id,
            action: log_data["action"],
            notes: log_data["notes"],
            created_at: created_at,
            updated_at: updated_at,
          )

        if existing
          logs_skipped += 1
          next
        end

        PatchClaimLog.create!(
          patch_id: patch_id,
          user_id: user_id,
          action: log_data["action"],
          notes: log_data["notes"],
          created_at: created_at,
          updated_at: updated_at,
        )
        logs_created += 1
      end

      puts "\r  Logs created: #{logs_created}                    "
      puts "  Logs skipped (duplicates/missing refs): #{logs_skipped}"
      puts ""

      # Phase 6: Recount ratings
      puts "Phase 6: Recounting patch ratings..."
      recounted = Patch.recount_all_ratings!
      puts "  Recounted #{recounted} patches"
      puts ""

      puts "Import complete!"
    end

    def find_or_create_import_user(user_data)
      email = user_data["email"]
      username = user_data["username"]
      name = user_data["name"]

      # Try email match first
      if email.present?
        user = User.find_by_email(email)
        return user if user
      end

      # Try username match
      if username.present?
        user = User.find_by(username_lower: username.downcase)
        return user if user
      end

      # Create staged user
      user_email = email.presence || "imported_#{SecureRandom.hex(8)}@placeholder.invalid"
      user_username = username.presence || "imported_#{SecureRandom.hex(6)}"

      # Ensure unique username
      base_username = user_username
      counter = 1
      while User.exists?(username_lower: user_username.downcase)
        user_username = "#{base_username}_#{counter}"
        counter += 1
      end

      User.create!(
        email: user_email,
        username: user_username,
        name: name,
        staged: true,
        active: false,
      )
    end
  end
end
