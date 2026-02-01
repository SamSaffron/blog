# frozen_string_literal: true

class HotOrNotController < ApplicationController
  requires_login
  skip_before_action :check_xhr
  helper HotOrNotHelper

  layout "hot_or_not"

  def index
    @patch = Patch.random_unrated_for(current_user)
    if @patch
      redirect_to "/hot-or-not/#{@patch.id}"
    else
      @user_stats = PatchRating.user_stats(current_user)
      render :all_rated
    end
  end

  def show
    # Admins can view inactive patches, regular users cannot
    @patch = current_user&.admin? ? Patch.find(params[:id]) : Patch.active.find(params[:id])
    @user_rating = @patch.user_rating(current_user)
    @user_stats = PatchRating.user_stats(current_user)

    # Navigation - order by id for consistent prev/next (active only)
    @prev_patch = Patch.active.where("id < ?", @patch.id).order(id: :desc).first
    @next_patch = Patch.active.where("id > ?", @patch.id).order(id: :asc).first
  end

  def rate
    @patch = Patch.active.find(params[:id])
    @rating = PatchRating.find_or_initialize_by(patch: @patch, user: current_user)
    @rating.is_hot = params[:is_hot] == "true"

    if @rating.save
      vote_text = @rating.is_hot ? "HOT" : "NOT"
      next_patch = Patch.random_unrated_for(current_user)
      if next_patch
        redirect_to "/hot-or-not/#{next_patch.id}", notice: "Voted #{vote_text} on \"#{@patch.title.truncate(50)}\""
      else
        redirect_to "/hot-or-not", notice: "Voted #{vote_text}! You've rated all patches!"
      end
    else
      redirect_to "/hot-or-not/#{@patch.id}", alert: "Error saving rating"
    end
  end

  def leaderboard
    @top_raters = PatchRating.leaderboard(limit: 20)
    @hottest_patches = Patch.active.where("hot_count + not_count > 0").by_hot_ratio.limit(10)
    @most_controversial = Patch.active.where("hot_count + not_count >= 5").most_controversial.limit(10)
    @user_stats = PatchRating.user_stats(current_user)
  end

  def stats
    @user_stats = PatchRating.user_stats(current_user)
    @recent_ratings = PatchRating.where(user_id: current_user.id).includes(:patch).order(created_at: :desc).limit(20)
  end

  def download
    @patch = Patch.active.find(params[:id])
    filename = "#{@patch.commit_hash[0..7]}.patch"
    send_data @patch.diff_content, filename: filename, type: "text/x-patch", disposition: "attachment"
  end
end
