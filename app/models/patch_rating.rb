# frozen_string_literal: true

class PatchRating < ActiveRecord::Base
  belongs_to :patch
  belongs_to :user

  validates :patch_id, presence: true
  validates :user_id, presence: true
  validates :is_hot, inclusion: { in: [true, false] }
  validates :patch_id, uniqueness: { scope: :user_id }

  after_commit :increment_counters, on: :create
  after_commit :update_counters_on_change, on: :update
  after_commit :decrement_counters, on: :destroy

  def self.user_stats(user)
    return nil unless user

    # Single aggregate query for rating counts
    stats =
      where(user_id: user.id).pick(
        Arel.sql("COUNT(*)::int"),
        Arel.sql("SUM(CASE WHEN is_hot THEN 1 ELSE 0 END)::int"),
        Arel.sql("SUM(CASE WHEN is_hot THEN 0 ELSE 1 END)::int"),
      )

    total_rated = stats[0] || 0
    hot_votes = stats[1] || 0
    not_votes = stats[2] || 0

    # Separate query for remaining (needs subquery)
    remaining = Patch.active.where.not(id: select(:patch_id).where(user_id: user.id)).count

    { total_rated: total_rated, hot_votes: hot_votes, not_votes: not_votes, remaining: remaining }
  end

  def self.leaderboard(limit: 10)
    User
      .joins(:patch_ratings)
      .group("users.id")
      .select("users.*, COUNT(patch_ratings.id)::int as rating_count")
      .order("rating_count DESC")
      .limit(limit)
  end

  private

  def increment_counters
    if is_hot
      Patch.where(id: patch_id).update_all("hot_count = hot_count + 1")
    else
      Patch.where(id: patch_id).update_all("not_count = not_count + 1")
    end
  end

  def decrement_counters
    if is_hot
      Patch.where(id: patch_id).update_all("hot_count = GREATEST(hot_count - 1, 0)")
    else
      Patch.where(id: patch_id).update_all("not_count = GREATEST(not_count - 1, 0)")
    end
  end

  def update_counters_on_change
    return unless saved_change_to_is_hot?

    if is_hot
      # Changed from NOT to HOT
      Patch.where(id: patch_id).update_all(
        "hot_count = hot_count + 1, not_count = GREATEST(not_count - 1, 0)",
      )
    else
      # Changed from HOT to NOT
      Patch.where(id: patch_id).update_all(
        "not_count = not_count + 1, hot_count = GREATEST(hot_count - 1, 0)",
      )
    end
  end
end
