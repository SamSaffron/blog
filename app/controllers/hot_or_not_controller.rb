# frozen_string_literal: true

class HotOrNotController < ApplicationController
  skip_before_action :check_xhr
  before_action :ensure_logged_in
  before_action :set_current_user_github_info
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
    @is_reviewer = is_reviewer?

    # Navigation - order by id for consistent prev/next (active only)
    @prev_patch = Patch.active.where("id < ?", @patch.id).order(id: :desc).first
    @next_patch = Patch.active.where("id > ?", @patch.id).order(id: :asc).first
  end

  def rate
    @patch = Patch.active.find(params[:id])

    if @patch.resolved?
      redirect_to "/hot-or-not/#{@patch.id}", alert: "Cannot vote on resolved patches"
      return
    end

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

  def my_patches
    unless @current_user_github_id
      redirect_to "/hot-or-not", alert: "Link your GitHub account to see your patches"
      return
    end

    @patches = Patch.active.by_github_id(@current_user_github_id).by_hot_ratio
    @committer_stats = calculate_committer_stats(@patches)
    @user_stats = PatchRating.user_stats(current_user)
  end

  def list
    @patches = Patch.active.includes(:committer, :patch_claims)

    # Apply filters
    case params[:status]
    when "resolved"
      @patches = @patches.resolved
    when "unresolved"
      @patches = @patches.unresolved
    when "fixed"
      @patches = @patches.where(resolution_status: "fixed")
    when "invalid"
      @patches = @patches.where(resolution_status: "invalid")
    end

    if params[:claimed] == "1"
      @patches = @patches.joins(:patch_claims).distinct
    elsif params[:claimed] == "0"
      @patches = @patches.left_joins(:patch_claims).where(patch_claims: { id: nil })
    end

    if params[:claimed_by_me] == "1" && current_user
      @patches = @patches.joins(:patch_claims).where(patch_claims: { user_id: current_user.id }).distinct
    end

    # Sorting
    @patches = case params[:sort]
    when "hot"
      @patches.by_hot_ratio
    when "controversial"
      @patches.most_controversial
    when "newest"
      @patches.order(created_at: :desc)
    when "oldest"
      @patches.order(created_at: :asc)
    else
      @patches.order(Arel.sql("(hot_count + not_count) DESC, created_at DESC"))
    end

    # Pagination
    @page = (params[:page] || 1).to_i
    @per_page = 50
    @total_count = @patches.count
    @total_pages = (@total_count.to_f / @per_page).ceil
    @patches = @patches.offset((@page - 1) * @per_page).limit(@per_page)

    @user_stats = PatchRating.user_stats(current_user)
    @is_reviewer = is_reviewer?
    @current_filter = params[:status]
    @current_sort = params[:sort] || "default"
  end

  def claim
    ensure_reviewer!
    @patch = Patch.active.find(params[:id])

    if @patch.resolved?
      redirect_to "/hot-or-not/#{@patch.id}", alert: "Cannot claim resolved patches"
      return
    end

    purpose = params[:purpose]

    if PatchClaim::PURPOSES.exclude?(purpose)
      redirect_to "/hot-or-not/#{@patch.id}", alert: "Invalid claim purpose"
      return
    end

    if @patch.claimed_by?(current_user, purpose: purpose)
      redirect_to "/hot-or-not/#{@patch.id}", alert: "You have already claimed this patch for #{purpose}"
      return
    end

    @patch.claim_for(current_user, purpose: purpose, notes: params[:notes])
    redirect_to "/hot-or-not/#{@patch.id}", notice: "Claimed patch for #{purpose}"
  end

  def unclaim
    ensure_reviewer!
    @patch = Patch.active.find(params[:id])
    purpose = params[:purpose]

    @patch.unclaim_for(current_user, purpose: purpose)
    redirect_to "/hot-or-not/#{@patch.id}", notice: "Unclaimed patch"
  end

  def resolve
    ensure_reviewer!
    @patch = Patch.active.find(params[:id])
    status = params[:status]

    if %w[fixed invalid].exclude?(status)
      redirect_to "/hot-or-not/#{@patch.id}", alert: "Invalid resolution status"
      return
    end

    @patch.resolve!(user: current_user, status: status, notes: params[:notes])
    redirect_to "/hot-or-not/#{@patch.id}", notice: "Patch marked as #{status}"
  end

  def unresolve
    raise Discourse::InvalidAccess unless current_user&.admin?

    @patch = Patch.find(params[:id])
    @patch.unresolve!
    redirect_to "/hot-or-not/#{@patch.id}", notice: "Patch resolution cleared"
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

  def reviewer_group_ids
    SiteSetting.hot_or_not_reviewers_groups_map
  end

  def is_reviewer?
    return false unless current_user
    return false if reviewer_group_ids.empty?
    current_user.in_any_groups?(reviewer_group_ids)
  end

  def ensure_reviewer!
    raise Discourse::InvalidAccess unless is_reviewer?
  end

  def set_current_user_github_info
    return unless current_user

    github_account =
      UserAssociatedAccount.find_by(user_id: current_user.id, provider_name: "github")

    if github_account
      @current_user_github_id = github_account.provider_uid&.to_i
      @current_user_github_username = github_account.info&.dig("nickname")
    end
  end
end
