# frozen_string_literal: true

class TopicShareToken < ActiveRecord::Base
  belongs_to :topic
  belongs_to :user

  validates :topic_id, presence: true
  validates :user_id, presence: true
  validates :token, uniqueness: true, if: :token?

  before_validation :generate_token, on: :create
  before_validation :set_expires_at, on: :create

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  def expired?
    expires_at <= Time.current
  end

  def active?
    !expired?
  end

  def self.find_by_token(token)
    find_by(token: token)
  end

  def self.cleanup_expired
    expired.delete_all
  end

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32) if token.blank?
  end

  def set_expires_at
    self.expires_at = 30.days.from_now if expires_at.blank?
  end
end
