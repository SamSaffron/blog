# frozen_string_literal: true

class CreateTopicShareTokens < ActiveRecord::Migration[7.0]
  def change
    create_table :topic_share_tokens do |t|
      t.string :token, null: false, index: { unique: true }
      t.references :topic, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :topic_share_tokens, %i[topic_id user_id]
    add_index :topic_share_tokens, :expires_at
  end
end

