# frozen_string_literal: true

class PatchClaimLog < ActiveRecord::Base
  belongs_to :patch
  belongs_to :user

  validates :patch_id, presence: true
  validates :user_id, presence: true
  validates :action, presence: true, inclusion: { in: %w[claimed unclaimed] }

  scope :claims, -> { where(action: "claimed") }
  scope :unclaims, -> { where(action: "unclaimed") }
end
