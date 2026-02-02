# frozen_string_literal: true

class PatchRating < ActiveRecord::Base
  belongs_to :patch
  belongs_to :user

  validates :patch_id, presence: true
  validates :user_id, presence: true
  validates :is_useful, inclusion: { in: [true, false] }
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
        Arel.sql("SUM(CASE WHEN is_useful THEN 1 ELSE 0 END)::int"),
        Arel.sql("SUM(CASE WHEN is_useful THEN 0 ELSE 1 END)::int"),
      )

    total_rated = stats[0] || 0
    useful_votes = stats[1] || 0
    not_useful_votes = stats[2] || 0

    # Separate query for remaining (needs subquery)
    remaining = Patch.active.where.not(id: select(:patch_id).where(user_id: user.id)).count

    { total_rated: total_rated, useful_votes: useful_votes, not_useful_votes: not_useful_votes, remaining: remaining }
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
    if is_useful
      Patch.where(id: patch_id).update_all("useful_count = useful_count + 1")
    else
      Patch.where(id: patch_id).update_all("not_useful_count = not_useful_count + 1")
    end
  end

  def decrement_counters
    if is_useful
      Patch.where(id: patch_id).update_all("useful_count = GREATEST(useful_count - 1, 0)")
    else
      Patch.where(id: patch_id).update_all("not_useful_count = GREATEST(not_useful_count - 1, 0)")
    end
  end

  def update_counters_on_change
    return unless saved_change_to_is_useful?

    if is_useful
      # Changed from NOT USEFUL to USEFUL
      Patch.where(id: patch_id).update_all(
        "useful_count = useful_count + 1, not_useful_count = GREATEST(not_useful_count - 1, 0)",
      )
    else
      # Changed from USEFUL to NOT USEFUL
      Patch.where(id: patch_id).update_all(
        "not_useful_count = not_useful_count + 1, useful_count = GREATEST(useful_count - 1, 0)",
      )
    end
  end
end
