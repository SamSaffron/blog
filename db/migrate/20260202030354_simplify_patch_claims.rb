# frozen_string_literal: true

class SimplifyPatchClaims < ActiveRecord::Migration[7.0]
  def up
    # First, remove duplicates keeping the most recent claim per patch/user
    execute <<~SQL
      DELETE FROM patch_claims pc1
      USING patch_claims pc2
      WHERE pc1.patch_id = pc2.patch_id
        AND pc1.user_id = pc2.user_id
        AND pc1.id < pc2.id
    SQL

    # Remove the old unique index that includes purpose
    remove_index :patch_claims, %i[patch_id user_id purpose]

    # Add new unique index without purpose
    add_index :patch_claims, %i[patch_id user_id], unique: true

    # Column drop happens in post-deployment migration
  end

  def down
    # Remove the new index
    remove_index :patch_claims, %i[patch_id user_id]

    # Re-add the old index
    add_index :patch_claims, %i[patch_id user_id purpose], unique: true
  end
end
