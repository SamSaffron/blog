#frozen_string_literal: true

class GptRating < ActiveRecord::Base
  belongs_to :post
  validates :post_id, presence: true, uniqueness: true
end
