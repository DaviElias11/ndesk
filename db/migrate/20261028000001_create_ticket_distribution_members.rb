# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class CreateTicketDistributionMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_distribution_members, id: :integer do |t|
      t.references :user, null: false, type: :integer, foreign_key: { to_table: :users }
      t.string   :level, limit: 2, null: false
      t.boolean  :active, null: false, default: true
      t.datetime :last_assigned_at, limit: 3, null: true
      t.column   :created_by_id, :integer, null: false
      t.column   :updated_by_id, :integer, null: false

      t.timestamps limit: 3

      t.index %i[user_id level], unique: true
    end

    return if column_exists?(:users, :discord_uid)

    add_column :users, :discord_uid, :string, limit: 30, null: true
    User.reset_column_information
  end
end
