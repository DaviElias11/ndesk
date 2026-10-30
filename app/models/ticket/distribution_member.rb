# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Ticket::DistributionMember < ApplicationModel
  include HasDefaultModelUserRelations

  LEVELS = %w[n1 n2].freeze

  belongs_to :user

  validates :level, inclusion: { in: LEVELS }
  validates :user_id, uniqueness: { scope: :level }

  scope :n1, -> { where(level: 'n1') }
  scope :n2, -> { where(level: 'n2') }
  scope :switched_on, -> { where(active: true) }
  scope :by_turn, -> { order(Arel.sql('last_assigned_at ASC NULLS FIRST'), :id) }
end
