# frozen_string_literal: true

class HotOrNotController < ApplicationController
  skip_before_action :check_xhr
  before_action :ensure_logged_in
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
    @hottest_patches =
      Patch.active.includes(:committer).where("hot_count + not_count > 0").by_hot_ratio.limit(10)
    @most_controversial =
      Patch.active.includes(:committer).where("hot_count + not_count >= 5").most_controversial.limit(10)
    @top_committers = top_committers_query(10)
    @user_stats = PatchRating.user_stats(current_user)
  end

  def by_committer
    @committer = params[:committer]
    @patches =
      Patch
        .active
        .includes(:committer)
        .where("committer_github_username = ? OR committer_name = ?", @committer, @committer)
        .by_hot_ratio
    @committer_stats = calculate_committer_stats(@patches)
    @user_stats = PatchRating.user_stats(current_user)
  end

  def stats
    @user_stats = PatchRating.user_stats(current_user)
    @recent_ratings =
      PatchRating.where(user_id: current_user.id).includes(:patch).order(created_at: :desc).limit(20)
  end

  def download
    @patch = Patch.active.find(params[:id])
    filename = "#{@patch.commit_hash[0..7]}.patch"
    send_data @patch.diff_content, filename: filename, type: "text/x-patch", disposition: "attachment"
  end

  private

  def top_committers_query(limit)
    Patch
      .active
      .where("hot_count + not_count > 0")
      .where(
        "NULLIF(committer_github_username, '') IS NOT NULL OR NULLIF(committer_name, '') IS NOT NULL",
      )
      .group("COALESCE(NULLIF(committer_github_username, ''), NULLIF(committer_name, ''))")
      .select(
        "COALESCE(NULLIF(committer_github_username, ''), NULLIF(committer_name, '')) as committer_identifier",
        "COUNT(*) as patch_count",
        "AVG(CASE WHEN (hot_count + not_count) > 0 THEN hot_count::float / (hot_count + not_count) ELSE 0 END) as avg_hot_ratio",
        "SUM(hot_count + not_count) as total_votes",
      )
      .order("avg_hot_ratio DESC")
      .limit(limit)
  end

  def calculate_committer_stats(patches)
    total_patches = patches.count
    rated_patches = patches.where("hot_count + not_count > 0")
    total_votes = rated_patches.sum("hot_count + not_count")
    total_hot = rated_patches.sum(:hot_count)
    avg_ratio = total_votes > 0 ? (total_hot.to_f / total_votes * 100).round(1) : 0

    { total_patches: total_patches, total_votes: total_votes, avg_hot_ratio: avg_ratio }
  end

  def ensure_logged_in
    return if current_user
    redirect_to("/login", allow_other_host: false) && return
  end
end
