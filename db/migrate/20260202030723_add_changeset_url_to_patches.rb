# frozen_string_literal: true

class AddChangesetUrlToPatches < ActiveRecord::Migration[7.0]
  def change
    add_column :patches, :resolution_changeset_url, :string
  end
end
