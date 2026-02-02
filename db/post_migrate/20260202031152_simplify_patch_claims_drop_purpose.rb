# frozen_string_literal: true

class SimplifyPatchClaimsDropPurpose < ActiveRecord::Migration[8.0]
  def up
    remove_column :patch_claims, :purpose
  end

  def down
    add_column :patch_claims, :purpose, :string, null: false, default: "fix"
    change_column_default :patch_claims, :purpose, nil
  end
end
