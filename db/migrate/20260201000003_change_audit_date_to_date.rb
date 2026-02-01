# frozen_string_literal: true

class ChangeAuditDateToDate < ActiveRecord::Migration[7.0]
  def up
    change_column :patches, :audit_date, :date
  end

  def down
    change_column :patches, :audit_date, :datetime
  end
end
