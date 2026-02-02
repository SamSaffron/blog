# frozen_string_literal: true

class PatchClaim < ActiveRecord::Base
  PURPOSES = %w[review fix].freeze

  belongs_to :patch
  belongs_to :user

  validates :patch_id, presence: true
  validates :user_id, presence: true
  validates :purpose, presence: true, inclusion: { in: PURPOSES }
  validates :patch_id, uniqueness: { scope: %i[user_id purpose] }
end
