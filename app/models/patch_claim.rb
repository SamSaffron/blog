# frozen_string_literal: true

class PatchClaim < ActiveRecord::Base
  self.ignored_columns = ["purpose"]

  belongs_to :patch
  belongs_to :user

  validates :patch_id, presence: true
  validates :user_id, presence: true
  validates :patch_id, uniqueness: { scope: :user_id }
end
