# frozen_string_literal: true

class AddCommitterNameIndexToPatches < ActiveRecord::Migration[7.0]
  def change
    add_index :patches, :committer_name
  end
end
