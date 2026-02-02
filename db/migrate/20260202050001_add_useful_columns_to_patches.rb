# frozen_string_literal: true

class AddUsefulColumnsToPatches < ActiveRecord::Migration[7.0]
  def change
    add_column :patches, :useful_count, :integer, default: 0, null: false
    add_column :patches, :not_useful_count, :integer, default: 0, null: false
    add_column :patch_ratings, :is_useful, :boolean
  end
end
