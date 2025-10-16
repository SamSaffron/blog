# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Topic Share Token Access", type: :system do
  fab!(:admin)
  fab!(:group)
  fab!(:category) { Fabricate(:category, read_restricted: true) }
  fab!(:topic) do
    Fabricate(:topic, category: category, title: "This is a Secret Topic for Testing")
  end
  fab!(:post) { Fabricate(:post, topic: topic) }

  before do
    # Make category fully restricted
    category.set_permissions(group => :full)
    category.save!
  end

  it "allows anonymous users to access restricted topics with valid share tokens" do
    # Create a share token as admin
    token = TopicShareToken.create!(topic: topic, user: admin)

    # Visit topic WITHOUT token - should get 404/403
    visit "/t/#{topic.slug}/#{topic.id}"
    expect(page).to have_no_content("This is a Secret Topic")

    # Visit topic WITH valid token - should see the topic
    visit "/t/#{topic.slug}/#{topic.id}?token=#{token.token}"
    expect(page).to have_content("This is a Secret Topic")
    expect(page).to have_content(post.raw)
  end

  it "denies access with expired tokens" do
    # Create an expired token
    token = TopicShareToken.create!(topic: topic, user: admin)
    token.update!(expires_at: 1.day.ago)

    # Visit topic with expired token - should get 404/403
    visit "/t/#{topic.slug}/#{topic.id}?token=#{token.token}"
    expect(page).to have_no_content("This is a Secret Topic")
  end

  it "denies access with invalid tokens" do
    # Visit topic with invalid token - should get 404/403
    visit "/t/#{topic.slug}/#{topic.id}?token=invalid_token_xyz"
    expect(page).to have_no_content("This is a Secret Topic")
  end

  it "denies access with token for different topic" do
    other_topic = Fabricate(:topic, category: category, title: "Another Secret Topic for Testing")
    token = TopicShareToken.create!(topic: other_topic, user: admin)

    # Try to access first topic with token for second topic - should fail
    visit "/t/#{topic.slug}/#{topic.id}?token=#{token.token}"
    expect(page).to have_no_content("This is a Secret Topic")
  end

  it "works with multiple sequential requests" do
    token = TopicShareToken.create!(topic: topic, user: admin)

    # Visit with token - should work
    visit "/t/#{topic.slug}/#{topic.id}?token=#{token.token}"
    expect(page).to have_content("This is a Secret Topic")

    # Visit without token - should fail (verifies Thread.current is cleaned up)
    visit "/t/#{topic.slug}/#{topic.id}"
    expect(page).to have_no_content("This is a Secret Topic")

    # Visit with token again - should work (verifies it can be set again)
    visit "/t/#{topic.slug}/#{topic.id}?token=#{token.token}"
    expect(page).to have_content("This is a Secret Topic")
  end
end
