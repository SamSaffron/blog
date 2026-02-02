# frozen_string_literal: true

class AddResolutionAndGithubIdToPatches < ActiveRecord::Migration[7.0]
  def change
    add_column :patches, :resolved_at, :datetime
    add_column :patches, :resolved_by_id, :integer
    add_column :patches, :resolution_status, :string
    add_column :patches, :resolution_notes, :text
    add_column :patches, :committer_github_id, :bigint

    add_index :patches, :resolved_by_id
    add_index :patches, :committer_github_id

    # Reset committer data to nil so backfill job can repopulate with GitHub IDs
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE patches SET
            committer_email = NULL,
            committer_name = NULL,
            committer_github_username = NULL,
            committer_user_id = NULL
        SQL
      end
    end
  end
end
