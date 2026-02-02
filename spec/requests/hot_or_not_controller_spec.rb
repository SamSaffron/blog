# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotOrNotController do
  fab!(:user)
  fab!(:reviewer_group) { Fabricate(:group) }
  fab!(:reviewer) { Fabricate(:user, groups: [reviewer_group]) }

  before do
    SiteSetting.hot_or_not_reviewers_groups = reviewer_group.id.to_s
  end

  describe "#list" do
    fab!(:patch1) { Patch.create!(commit_hash: "abc1234", title: "Test patch 1", active: true) }
    fab!(:patch2) { Patch.create!(commit_hash: "def5678", title: "Test patch 2", active: true) }

    before do
      sign_in(user)
    end

    it "returns all patches without filters" do
      get "/hot-or-not/list"
      expect(response.status).to eq(200)
    end

    it "filters to claimed patches" do
      PatchClaim.create!(patch: patch1, user: reviewer)

      get "/hot-or-not/list", params: { claimed: "1" }
      expect(response.status).to eq(200)
      expect(response.body).to include(patch1.title)
      expect(response.body).not_to include(patch2.title)
    end

    it "filters to unclaimed patches" do
      PatchClaim.create!(patch: patch1, user: reviewer)

      get "/hot-or-not/list", params: { claimed: "0" }
      expect(response.status).to eq(200)
      expect(response.body).not_to include(patch1.title)
      expect(response.body).to include(patch2.title)
    end

    it "sorts by newest" do
      get "/hot-or-not/list", params: { sort: "newest" }
      expect(response.status).to eq(200)
    end

    it "sorts by oldest" do
      get "/hot-or-not/list", params: { sort: "oldest" }
      expect(response.status).to eq(200)
    end

    it "sorts by hot ratio" do
      get "/hot-or-not/list", params: { sort: "hot" }
      expect(response.status).to eq(200)
    end

    it "combines claimed filter with sorting" do
      PatchClaim.create!(patch: patch1, user: reviewer)

      get "/hot-or-not/list", params: { claimed: "1", sort: "newest" }
      expect(response.status).to eq(200)
    end
  end

  describe "#resolve" do
    fab!(:patch) { Patch.create!(commit_hash: "abc1234", title: "Test patch", active: true) }

    before do
      sign_in(reviewer)
    end

    it "accepts valid https changeset URL" do
      post "/hot-or-not/#{patch.id}/resolve",
           params: {
             status: "fixed",
             changeset_url: "https://github.com/discourse/discourse/commit/abc123",
           }
      expect(response).to redirect_to("/hot-or-not/#{patch.id}")
      expect(flash[:notice]).to include("fixed")
      patch.reload
      expect(patch.resolution_status).to eq("fixed")
      expect(patch.resolution_changeset_url).to eq("https://github.com/discourse/discourse/commit/abc123")
    end

    it "accepts valid http changeset URL" do
      post "/hot-or-not/#{patch.id}/resolve",
           params: {
             status: "fixed",
             changeset_url: "http://example.com/commit/123",
           }
      expect(response).to redirect_to("/hot-or-not/#{patch.id}")
      patch.reload
      expect(patch.resolution_status).to eq("fixed")
    end

    it "rejects javascript: URLs" do
      post "/hot-or-not/#{patch.id}/resolve",
           params: {
             status: "fixed",
             changeset_url: "javascript:alert('xss')",
           }
      expect(response).to redirect_to("/hot-or-not/#{patch.id}")
      expect(flash[:alert]).to include("valid HTTP or HTTPS URL")
      patch.reload
      expect(patch.resolution_status).to be_nil
    end

    it "rejects data: URLs" do
      post "/hot-or-not/#{patch.id}/resolve",
           params: {
             status: "fixed",
             changeset_url: "data:text/html,<script>alert('xss')</script>",
           }
      expect(response).to redirect_to("/hot-or-not/#{patch.id}")
      expect(flash[:alert]).to include("valid HTTP or HTTPS URL")
      patch.reload
      expect(patch.resolution_status).to be_nil
    end

    it "requires changeset URL when resolving as fixed" do
      post "/hot-or-not/#{patch.id}/resolve", params: { status: "fixed" }
      expect(response).to redirect_to("/hot-or-not/#{patch.id}")
      expect(flash[:alert]).to include("required")
      patch.reload
      expect(patch.resolution_status).to be_nil
    end

    it "does not require changeset URL when resolving as invalid" do
      post "/hot-or-not/#{patch.id}/resolve", params: { status: "invalid" }
      expect(response).to redirect_to("/hot-or-not/#{patch.id}")
      expect(flash[:notice]).to include("invalid")
      patch.reload
      expect(patch.resolution_status).to eq("invalid")
    end
  end
end
