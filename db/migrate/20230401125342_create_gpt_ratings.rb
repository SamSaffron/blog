# frozen_string_literal: true

class CreateGptRatings < ActiveRecord::Migration[7.0]
  def change
    create_table :gpt_ratings do |t|
      t.float :wish_score
      t.float :corruption_score
      t.integer :post_id

      t.timestamps
    end

    add_index :gpt_ratings, %i[post_id], unique: true
  end
end
