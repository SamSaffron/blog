# frozen_string_literal: true

class CreatePatchClaimLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :patch_claim_logs do |t|
      t.integer :patch_id, null: false
      t.integer :user_id, null: false
      t.string :action, null: false
      t.text :notes
      t.timestamps
    end

    add_index :patch_claim_logs, :patch_id
    add_index :patch_claim_logs, :user_id
    add_index :patch_claim_logs, :created_at

    execute <<~SQL
      DELETE FROM patch_claims
      WHERE patch_id IN (
        SELECT id FROM patches WHERE resolved_at IS NOT NULL
      )
    SQL
  end
end
