# frozen_string_literal: true

class CreatePatches < ActiveRecord::Migration[7.0]
  def change
    create_table :patches do |t|
      t.string :commit_hash, null: false
      t.string :title, null: false
      t.text :summary
      t.text :markdown_content
      t.text :diff_content
      t.string :issue_type
      t.datetime :audit_date
      t.string :repository
      t.integer :hot_count, default: 0, null: false
      t.integer :not_count, default: 0, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :patches, :commit_hash, unique: true
    add_index :patches, :active
    add_index :patches, :audit_date
  end
end
