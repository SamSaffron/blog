# frozen_string_literal: true

require "rails_helper"

RSpec.describe TopicShareToken, type: :model do
  fab!(:topic)
  fab!(:user)

  describe "validations" do
    it "requires a topic" do
      token = TopicShareToken.new(user: user)
      expect(token).not_to be_valid
      expect(token.errors[:topic_id]).to be_present
    end

    it "requires a user" do
      token = TopicShareToken.new(topic: topic)
      expect(token).not_to be_valid
      expect(token.errors[:user_id]).to be_present
    end

    it "enforces token uniqueness" do
      token1 = TopicShareToken.create!(topic: topic, user: user)
      token2 = TopicShareToken.new(topic: topic, user: user, token: token1.token)
      expect(token2).not_to be_valid
      expect(token2.errors[:token]).to be_present
    end
  end

  describe "callbacks" do
    it "generates a token on create" do
      token = TopicShareToken.create!(topic: topic, user: user)
      expect(token.token).to be_present
      expect(token.token.length).to be > 32
    end

    it "sets expires_at to 30 days from now" do
      token = TopicShareToken.create!(topic: topic, user: user)
      expect(token.expires_at).to be_within(1.minute).of(30.days.from_now)
    end
  end

  describe "scopes" do
    let!(:active_token) { TopicShareToken.create!(topic: topic, user: user) }
    let!(:expired_token) do
      token = TopicShareToken.create!(topic: topic, user: user)
      token.update!(expires_at: 1.day.ago)
      token
    end

    it "finds active tokens" do
      expect(TopicShareToken.active).to include(active_token)
      expect(TopicShareToken.active).not_to include(expired_token)
    end

    it "finds expired tokens" do
      expect(TopicShareToken.expired).to include(expired_token)
      expect(TopicShareToken.expired).not_to include(active_token)
    end
  end

  describe "instance methods" do
    let(:token) { TopicShareToken.create!(topic: topic, user: user) }

    it "knows if it's expired" do
      expect(token.expired?).to be_falsey
      token.update!(expires_at: 1.day.ago)
      expect(token.expired?).to be_truthy
    end

    it "knows if it's active" do
      expect(token.active?).to be_truthy
      token.update!(expires_at: 1.day.ago)
      expect(token.active?).to be_falsey
    end
  end
end
