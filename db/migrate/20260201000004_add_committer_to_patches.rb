# frozen_string_literal: true

class AddCommitterToPatches < ActiveRecord::Migration[7.0]
  def change
    add_column :patches, :committer_email, :string
    add_column :patches, :committer_name, :string
    add_column :patches, :committer_github_username, :string
    add_column :patches, :committer_user_id, :integer

    add_index :patches, :committer_user_id
    add_index :patches, :committer_github_username
  end
end
