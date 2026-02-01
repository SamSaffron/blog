# frozen_string_literal: true

class CreatePatchRatings < ActiveRecord::Migration[7.0]
  def change
    create_table :patch_ratings do |t|
      t.references :patch, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :is_hot, null: false
      t.timestamps
    end

    add_index :patch_ratings, %i[patch_id user_id], unique: true
  end
end
