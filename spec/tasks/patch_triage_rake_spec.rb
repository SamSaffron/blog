# frozen_string_literal: true

require "rails_helper"

RSpec.describe "blog:patch_triage rake tasks" do
  fab!(:user_1, :user) do
    Fabricate(:user, username: "reviewer_one", email: "reviewer1@example.com")
  end
  fab!(:user_2, :user) do
    Fabricate(:user, username: "reviewer_two", email: "reviewer2@example.com")
  end
  fab!(:committer, :user) do
    Fabricate(:user, username: "committer_user", email: "committer@example.com")
  end
  fab!(:resolver, :user) do
    Fabricate(:user, username: "resolver_user", email: "resolver@example.com")
  end

  let(:export_path) { Rails.root.join("tmp", "patch_triage_test_export.json") }

  before do
    Rake::Task.clear
    Discourse::Application.load_tasks
  end

  after { FileUtils.rm_f(export_path) }

  describe "full export/import cycle" do
    let!(:patch_1) do
      Fabricate(
        :patch,
        commit_hash: "abc1234567890",
        title: "Fix security issue",
        summary: "Important security fix",
        markdown_content: "# Security Fix\n\nDetails here",
        diff_content: "diff --git a/file.rb",
        issue_type: "security",
        repository: "discourse (main)",
        active: true,
        committer_email: "dev@github.com",
        committer_name: "Dev User",
        committer_github_username: "devuser",
        committer_github_id: 12_345,
        committer_user_id: committer.id,
      )
    end

    let!(:patch_2) do
      Fabricate(
        :patch,
        commit_hash: "def7890123456",
        title: "Bug fix for login",
        summary: "Fixes login redirect",
        issue_type: "bug",
        repository: "discourse-ai",
        active: false,
        resolved_at: 3.days.ago,
        resolved_by_id: resolver.id,
        resolution_status: "fixed",
        resolution_notes: "Fixed in PR #999",
        resolution_changeset_url: "https://github.com/discourse/discourse/pull/999",
      )
    end

    let!(:rating_1) { PatchRating.create!(patch: patch_1, user: user_1, is_useful: true) }
    let!(:rating_2) { PatchRating.create!(patch: patch_1, user: user_2, is_useful: false) }
    let!(:rating_3) { PatchRating.create!(patch: patch_2, user: user_1, is_useful: true) }

    let!(:claim_1) { PatchClaim.create!(patch: patch_1, user: user_1, notes: "Working on review") }

    let!(:claim_log_1) do
      PatchClaimLog.create!(
        patch: patch_1,
        user: user_1,
        action: "claimed",
        notes: "Starting review",
      )
    end
    let!(:claim_log_2) do
      PatchClaimLog.create!(
        patch: patch_1,
        user: user_2,
        action: "claimed",
        notes: "Also reviewing",
      )
    end
    let!(:claim_log_3) do
      PatchClaimLog.create!(patch: patch_1, user: user_2, action: "unclaimed", notes: "Done")
    end

    before do
      patch_1.recount_ratings!
      patch_2.recount_ratings!

      rating_1.update_columns(created_at: 10.days.ago, updated_at: 10.days.ago)
      rating_2.update_columns(created_at: 9.days.ago, updated_at: 9.days.ago)
      rating_3.update_columns(created_at: 8.days.ago, updated_at: 8.days.ago)
      claim_1.update_columns(created_at: 7.days.ago, updated_at: 7.days.ago)
      claim_log_1.update_columns(created_at: 6.days.ago, updated_at: 6.days.ago)
      claim_log_2.update_columns(created_at: 5.days.ago, updated_at: 5.days.ago)
      claim_log_3.update_columns(created_at: 4.days.ago, updated_at: 4.days.ago)
      patch_1.update_columns(created_at: 20.days.ago, updated_at: 15.days.ago)
      patch_2.update_columns(created_at: 18.days.ago, updated_at: 12.days.ago)
    end

    it "exports and imports all data with preserved timestamps" do
      Rake::Task["blog:patch_triage:export"].invoke(export_path.to_s)

      exported_data = JSON.parse(File.read(export_path))
      expect(exported_data["counts"]["patches"]).to eq(2)
      expect(exported_data["counts"]["patch_ratings"]).to eq(3)
      expect(exported_data["counts"]["patch_claims"]).to eq(1)
      expect(exported_data["counts"]["patch_claim_logs"]).to eq(3)
      expect(exported_data["users"].size).to eq(4)

      original_patch_1_created = patch_1.created_at
      original_patch_1_updated = patch_1.updated_at
      original_rating_1_created = rating_1.created_at
      original_claim_1_created = claim_1.created_at

      PatchClaimLog.delete_all
      PatchClaim.delete_all
      PatchRating.delete_all
      Patch.delete_all

      expect(Patch.count).to eq(0)
      expect(PatchRating.count).to eq(0)

      Rake::Task["blog:patch_triage:import"].reenable
      Rake::Task["blog:patch_triage:import"].invoke(export_path.to_s)

      expect(Patch.count).to eq(2)
      expect(PatchRating.count).to eq(3)
      expect(PatchClaim.count).to eq(1)
      expect(PatchClaimLog.count).to eq(3)

      imported_patch_1 = Patch.find_by(commit_hash: "abc1234567890")
      expect(imported_patch_1.title).to eq("Fix security issue")
      expect(imported_patch_1.summary).to eq("Important security fix")
      expect(imported_patch_1.issue_type).to eq("security")
      expect(imported_patch_1.committer_user_id).to eq(committer.id)
      expect(imported_patch_1.committer_github_id).to eq(12_345)
      expect(imported_patch_1.useful_count).to eq(1)
      expect(imported_patch_1.not_useful_count).to eq(1)
      expect(imported_patch_1.created_at).to be_within(1.second).of(original_patch_1_created)
      expect(imported_patch_1.updated_at).to be_within(1.second).of(original_patch_1_updated)

      imported_patch_2 = Patch.find_by(commit_hash: "def7890123456")
      expect(imported_patch_2.resolved?).to be true
      expect(imported_patch_2.resolved_by_id).to eq(resolver.id)
      expect(imported_patch_2.resolution_status).to eq("fixed")
      expect(imported_patch_2.resolution_changeset_url).to eq(
        "https://github.com/discourse/discourse/pull/999",
      )

      imported_rating = PatchRating.find_by(patch: imported_patch_1, user: user_1)
      expect(imported_rating.is_useful).to be true
      expect(imported_rating.created_at).to be_within(1.second).of(original_rating_1_created)

      imported_claim = PatchClaim.find_by(patch: imported_patch_1, user: user_1)
      expect(imported_claim.notes).to eq("Working on review")
      expect(imported_claim.created_at).to be_within(1.second).of(original_claim_1_created)

      expect(PatchClaimLog.where(patch: imported_patch_1).count).to eq(3)
    end

    it "is re-runnable and updates existing records" do
      Rake::Task["blog:patch_triage:export"].invoke(export_path.to_s)

      patch_1.update!(title: "Modified title")
      rating_1.update_columns(is_useful: false)

      Rake::Task["blog:patch_triage:import"].reenable
      Rake::Task["blog:patch_triage:import"].invoke(export_path.to_s)

      expect(Patch.count).to eq(2)
      expect(PatchRating.count).to eq(3)

      expect(patch_1.reload.title).to eq("Fix security issue")
      expect(rating_1.reload.is_useful).to be true
    end

    it "skips duplicate claim logs on re-import" do
      Rake::Task["blog:patch_triage:export"].invoke(export_path.to_s)

      initial_count = PatchClaimLog.count

      Rake::Task["blog:patch_triage:import"].reenable
      Rake::Task["blog:patch_triage:import"].invoke(export_path.to_s)

      expect(PatchClaimLog.count).to eq(initial_count)
    end

    it "creates staged users when users don't exist" do
      Rake::Task["blog:patch_triage:export"].invoke(export_path.to_s)

      PatchClaimLog.delete_all
      PatchClaim.delete_all
      PatchRating.delete_all
      Patch.delete_all

      original_email = user_1.email
      user_1.destroy!

      Rake::Task["blog:patch_triage:import"].reenable
      Rake::Task["blog:patch_triage:import"].invoke(export_path.to_s)

      staged_user = User.find_by_email(original_email)
      expect(staged_user).to be_present
      expect(staged_user.staged).to be true

      imported_patch = Patch.find_by(commit_hash: "abc1234567890")
      expect(PatchRating.where(patch: imported_patch, user: staged_user).count).to eq(1)
    end

    it "creates export directory if it doesn't exist" do
      nested_path = Rails.root.join("tmp", "nested", "export", "test.json")
      FileUtils.rm_rf(Rails.root.join("tmp", "nested"))

      Rake::Task["blog:patch_triage:export"].reenable
      Rake::Task["blog:patch_triage:export"].invoke(nested_path.to_s)

      expect(File.exist?(nested_path)).to be true

      FileUtils.rm_rf(Rails.root.join("tmp", "nested"))
    end
  end

  describe "edge cases" do
    it "handles empty database gracefully" do
      Rake::Task["blog:patch_triage:export"].invoke(export_path.to_s)

      exported_data = JSON.parse(File.read(export_path))
      expect(exported_data["counts"]["patches"]).to eq(0)
      expect(exported_data["users"]).to be_empty
    end

    it "fails gracefully with missing file path on import" do
      expect { Rake::Task["blog:patch_triage:import"].invoke("nonexistent.json") }.to raise_error(
        SystemExit,
      )
    end
  end
end
