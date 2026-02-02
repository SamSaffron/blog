# frozen_string_literal: true

class CreatePatchClaims < ActiveRecord::Migration[7.0]
  def change
    create_table :patch_claims do |t|
      t.integer :patch_id, null: false
      t.integer :user_id, null: false
      t.string :purpose, null: false
      t.text :notes
      t.timestamps
    end

    add_index :patch_claims, %i[patch_id user_id purpose], unique: true
    add_index :patch_claims, :patch_id
    add_index :patch_claims, :user_id
  end
end
