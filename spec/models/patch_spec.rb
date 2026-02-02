# frozen_string_literal: true

require "rails_helper"

RSpec.describe Patch, type: :model do
  fab!(:user)
  fab!(:user_2, :user)

  let(:patch) { Fabricate(:patch) }

  describe "#claim_for" do
    it "creates a claim and logs it" do
      expect { patch.claim_for(user, notes: "working on it") }.to change { PatchClaimLog.count }.by(
        1,
      ).and change { PatchClaim.count }.by(1)

      log = PatchClaimLog.last
      expect(log.patch_id).to eq(patch.id)
      expect(log.user_id).to eq(user.id)
      expect(log.action).to eq("claimed")
      expect(log.notes).to eq("working on it")
    end

    it "is atomic - rolls back on failure" do
      allow_any_instance_of(PatchClaimLog).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

      expect {
        begin
          patch.claim_for(user)
        rescue StandardError
          nil
        end
      }.not_to change { PatchClaim.count }
    end
  end

  describe "#unclaim_for" do
    it "removes claim and logs it when claim exists" do
      patch.claim_for(user)

      expect { patch.unclaim_for(user) }.to change { PatchClaimLog.count }.by(1).and change {
              PatchClaim.count
            }.by(-1)

      log = PatchClaimLog.last
      expect(log.patch_id).to eq(patch.id)
      expect(log.user_id).to eq(user.id)
      expect(log.action).to eq("unclaimed")
    end

    it "does not log when user has no claim" do
      expect { patch.unclaim_for(user) }.not_to change { PatchClaimLog.count }
    end
  end

  describe "#resolve!" do
    it "unclaims all claimants and logs each" do
      patch.claim_for(user)
      patch.claim_for(user_2)

      expect { patch.resolve!(user: user, status: "invalid") }.to change {
        PatchClaimLog.unclaims.count
      }.by(2).and change { PatchClaim.count }.by(-2)

      logs = PatchClaimLog.unclaims.where(patch_id: patch.id).order(:user_id)
      expect(logs.map(&:user_id)).to contain_exactly(user.id, user_2.id)
      expect(logs.first.notes).to include("auto: patch resolved as invalid")
    end

    it "resolves without error when there are no claims" do
      expect { patch.resolve!(user: user, status: "invalid") }.not_to raise_error
      expect(patch.reload.resolved?).to be true
    end

    it "is atomic - rolls back on validation failure" do
      patch.claim_for(user)

      expect {
        begin
          patch.resolve!(user: user, status: "fixed", changeset_url: nil)
        rescue StandardError
          nil
        end
      }.not_to change { PatchClaim.count }
    end
  end
end
