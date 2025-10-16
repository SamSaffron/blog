# frozen_string_literal: true

require "rails_helper"

RSpec.describe Blog::TopicShareTokensController, type: :request do
  fab!(:admin)
  fab!(:user)
  fab!(:topic)

  describe "GET #index" do
    context "when admin" do
      it "returns a list of active tokens" do
        sign_in(admin)
        token = TopicShareToken.create!(topic: topic, user: admin)

        get "/topics/#{topic.id}/topic_share_tokens.json"

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json.first["token"]).to eq(token.token)
      end
    end

    context "when not admin" do
      it "denies access" do
        sign_in(user)

        get "/topics/#{topic.id}/topic_share_tokens.json"

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when not logged in" do
      it "requires login" do
        get "/topics/#{topic.id}/topic_share_tokens.json"

        expect(response.status).to eq(403)
      end
    end
  end

  describe "POST #create" do
    context "when admin" do
      it "creates a new token" do
        sign_in(admin)

        expect {
          post "/topics/#{topic.id}/topic_share_tokens.json"
        }.to change(TopicShareToken, :count).by(1)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json).to have_key("token")
        expect(json).to have_key("expires_at")
        expect(json).to have_key("share_url")
      end
    end

    context "when not admin" do
      it "denies access" do
        sign_in(user)

        post "/topics/#{topic.id}/topic_share_tokens.json"

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE #destroy" do
    context "when admin" do
      it "deletes the token" do
        sign_in(admin)
        token = TopicShareToken.create!(topic: topic, user: admin)

        expect {
          delete "/topics/#{topic.id}/topic_share_tokens/#{token.id}.json"
        }.to change(TopicShareToken, :count).by(-1)

        expect(response).to have_http_status(:success)
      end
    end

    context "when not admin" do
      it "denies access" do
        sign_in(user)
        token = TopicShareToken.create!(topic: topic, user: admin)

        delete "/topics/#{topic.id}/topic_share_tokens/#{token.id}.json"

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end