# frozen_string_literal: true

class CopyHotOrNotDataToUseful < ActiveRecord::Migration[7.0]
  def up
    execute "UPDATE patches SET useful_count = hot_count, not_useful_count = not_count"
    execute "UPDATE patch_ratings SET is_useful = is_hot"
  end

  def down
    execute "UPDATE patches SET hot_count = useful_count, not_count = not_useful_count"
    execute "UPDATE patch_ratings SET is_hot = is_useful"
  end
end
