# frozen_string_literal: true

class HotOrNotController < ApplicationController
  skip_before_action :check_xhr
  before_action :ensure_logged_in, except: [:token_download]
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

  MY_PATCHES_TABS = %w[authored claimed resolved].freeze

  def my_patches
    @tab = MY_PATCHES_TABS.include?(params[:tab]) ? params[:tab] : "authored"

    @patches =
      case @tab
      when "claimed"
        Patch.active.claimed_by(current_user).by_hot_ratio
      when "resolved"
        Patch.active.resolved_by(current_user).order(resolved_at: :desc)
      else # "authored"
        if @current_user_github_id
          Patch.active.by_github_id(@current_user_github_id).by_hot_ratio
        else
          Patch.none
        end
      end

    @tab_stats = calculate_patch_stats(@patches)
    @user_stats = PatchRating.user_stats(current_user)
  end

  USER_PROFILE_TABS = %w[claimed resolved authored].freeze

  def user_profile
    @user = User.find_by_username(params[:username])
    raise Discourse::NotFound unless @user

    @tab = USER_PROFILE_TABS.include?(params[:tab]) ? params[:tab] : "claimed"

    # Get GitHub ID for the user to look up authored patches
    github_account = UserAssociatedAccount.find_by(user_id: @user.id, provider_name: "github")
    user_github_id = github_account&.provider_uid&.to_i

    @patches =
      case @tab
      when "authored"
        if user_github_id
          Patch.active.by_github_id(user_github_id).by_hot_ratio
        else
          Patch.none
        end
      when "resolved"
        Patch.active.resolved_by(@user).order(resolved_at: :desc)
      else # "claimed"
        Patch.active.claimed_by(@user).by_hot_ratio
      end

    @tab_stats = calculate_patch_stats(@patches)
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
      @patches = @patches.where(id: PatchClaim.select(:patch_id))
    elsif params[:claimed] == "0"
      @patches = @patches.where.not(id: PatchClaim.select(:patch_id))
    end

    if params[:claimed_by_me] == "1" && current_user
      @patches = @patches.where(id: PatchClaim.where(user_id: current_user.id).select(:patch_id))
    end

    # Sorting
    @patches = case params[:sort]
    when "hot"
      @patches.by_hot_ratio
    when "controversial"
      @patches.most_controversial
    when "newest"
      @patches.order("patches.created_at DESC")
    when "oldest"
      @patches.order("patches.created_at ASC")
    else
      @patches.order(Arel.sql("(hot_count + not_count) DESC, patches.created_at DESC"))
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

    if @patch.claimed_by?(current_user)
      redirect_to "/hot-or-not/#{@patch.id}", alert: "You have already claimed this patch"
      return
    end

    @patch.claim_for(current_user, notes: params[:notes])
    redirect_to "/hot-or-not/#{@patch.id}", notice: "Patch claimed"
  end

  def unclaim
    ensure_reviewer!
    @patch = Patch.active.find(params[:id])

    @patch.unclaim_for(current_user)
    redirect_to "/hot-or-not/#{@patch.id}", notice: "Patch unclaimed"
  end

  def resolve
    ensure_reviewer!
    @patch = Patch.active.find(params[:id])
    status = params[:status]

    if %w[fixed invalid].exclude?(status)
      redirect_to "/hot-or-not/#{@patch.id}", alert: "Invalid resolution status"
      return
    end

    changeset_url = params[:changeset_url]&.strip.presence

    if status == "fixed" && changeset_url.blank?
      redirect_to "/hot-or-not/#{@patch.id}", alert: "Changeset URL is required when resolving as fixed"
      return
    end

    if status == "fixed" && !Patch.valid_changeset_url?(changeset_url)
      redirect_to "/hot-or-not/#{@patch.id}", alert: "Changeset URL must be a valid HTTP or HTTPS URL"
      return
    end

    # Only store changeset URL for "fixed" status
    changeset_url = nil unless status == "fixed"

    @patch.resolve!(user: current_user, status: status, notes: params[:notes], changeset_url: changeset_url)
    redirect_to "/hot-or-not/#{@patch.id}", notice: "Patch marked as #{status}"
  end

  def unresolve
    raise Discourse::InvalidAccess unless current_user&.admin?

    @patch = Patch.find(params[:id])
    @patch.unresolve!
    redirect_to "/hot-or-not/#{@patch.id}", notice: "Patch resolution cleared"
  end

  def leaderboard
    @top_resolvers = top_resolvers_query(10)
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

  def generate_download_token
    @patch = Patch.active.find(params[:id])
    token = PatchDownloadToken.generate(@patch.id)
    base_url = Discourse.base_url
    curl_command = "curl -sL '#{base_url}/hot-or-not/p/#{token}' | git apply"
    render json: { curl_command: curl_command }
  end

  def token_download
    patch_id = PatchDownloadToken.validate(params[:token])

    if patch_id.nil?
      render plain: "Token expired or invalid", status: :unauthorized
      return
    end

    @patch = Patch.active.find_by(id: patch_id)

    if @patch.nil?
      render plain: "Patch not found", status: :not_found
      return
    end

    render plain: @patch.diff_content, content_type: "text/plain"
  end

  private

  def top_resolvers_query(limit)
    Patch
      .active
      .resolved
      .joins("INNER JOIN users ON users.id = patches.resolved_by_id")
      .group("users.id, users.username")
      .select(
        "users.id as user_id",
        "users.username as username",
        "COUNT(*) as resolved_count",
        "SUM(CASE WHEN resolution_status = 'fixed' THEN 1 ELSE 0 END) as fixed_count",
        "SUM(CASE WHEN resolution_status = 'invalid' THEN 1 ELSE 0 END) as invalid_count",
      )
      .order("resolved_count DESC")
      .limit(limit)
  end

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
    calculate_patch_stats(patches)
  end

  def calculate_patch_stats(patches)
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
