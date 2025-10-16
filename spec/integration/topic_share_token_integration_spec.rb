# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Topic Share Token Integration" do
  fab!(:admin)
  fab!(:category) { Fabricate(:category, read_restricted: true) }
  fab!(:topic) { Fabricate(:topic, category: category) }

  before do
    # Make category fully restricted
    category.set_permissions({})
    category.save!
  end

  it "allows anonymous users to access restricted topics with valid share tokens" do
    # Create a share token as admin
    token = TopicShareToken.create!(topic: topic, user: admin)

    # Verify anonymous user can't see topic without token
    guardian_without_token = Guardian.new(nil)
    expect(guardian_without_token.can_see_topic?(topic)).to eq(false)

    # Verify anonymous user can see topic with valid token
    Thread.current[:share_token_value] = token.token
    guardian_with_token = Guardian.new(nil)
    expect(guardian_with_token.can_see_topic?(topic)).to eq(true)

    # Expire the token
    token.update!(expires_at: 1.day.ago)

    # Verify anonymous user can't see topic with expired token
    guardian_with_expired = Guardian.new(nil)
    expect(guardian_with_expired.can_see_topic?(topic)).to eq(false)

    # Clean up
    Thread.current[:share_token_value] = nil
  end

  it "generates unique tokens for each request" do
    token1 = TopicShareToken.create!(topic: topic, user: admin)
    token2 = TopicShareToken.create!(topic: topic, user: admin)

    expect(token1.token).not_to eq(token2.token)
  end

  it "cleans up expired tokens" do
    active_token = TopicShareToken.create!(topic: topic, user: admin)
    expired_token = TopicShareToken.create!(topic: topic, user: admin)
    expired_token.update!(expires_at: 1.day.ago)

    expect(TopicShareToken.count).to eq(2)
    TopicShareToken.cleanup_expired
    expect(TopicShareToken.count).to eq(1)
    expect(TopicShareToken.first).to eq(active_token)
  end
end
