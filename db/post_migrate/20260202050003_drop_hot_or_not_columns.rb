# frozen_string_literal: true

class DropHotOrNotColumns < ActiveRecord::Migration[7.0]
  DROPPED_COLUMNS = { patches: %i[hot_count not_count], patch_ratings: %i[is_hot] }

  def up
    DROPPED_COLUMNS.each do |table, columns|
      columns.each { |col| remove_column table, col }
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
