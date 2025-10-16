# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuardianPatch do
  fab!(:group)
  fab!(:category) { Fabricate(:category, read_restricted: true) }
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:user)
  fab!(:admin)

  before do
    category.set_permissions(group => :full)
    category.save!
  end

  describe "#can_see_topic?" do
    let(:token) { TopicShareToken.create!(topic: topic, user: admin) }
    let(:expired_token) do
      token = TopicShareToken.create!(topic: topic, user: admin)
      token.update!(expires_at: 1.day.ago)
      token
    end

    after { Thread.current[:share_token_value] = nil }

    it "allows anonymous users to see topics with valid tokens" do
      Thread.current[:share_token_value] = token.token
      guardian = Guardian.new(nil)

      expect(guardian.can_see_topic?(topic)).to eq(true)
    end

    it "denies anonymous users to see topics with expired tokens" do
      Thread.current[:share_token_value] = expired_token.token
      guardian = Guardian.new(nil)

      expect(guardian.can_see_topic?(topic)).to eq(false)
    end

    it "denies anonymous users to see topics with invalid tokens" do
      Thread.current[:share_token_value] = "invalid_token"
      guardian = Guardian.new(nil)

      expect(guardian.can_see_topic?(topic)).to eq(false)
    end

    it "denies anonymous users to see topics with wrong topic id" do
      other_topic = Fabricate(:topic)
      Thread.current[:share_token_value] = token.token
      guardian = Guardian.new(nil)

      expect(guardian.can_see_topic?(other_topic)).to eq(false)
    end

    it "allows authenticated users to see topics normally" do
      group.add(user)
      guardian = Guardian.new(user)

      expect(guardian.can_see_topic?(topic)).to eq(true)
    end
  end
end
