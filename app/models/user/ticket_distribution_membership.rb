# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Keeps the N1/N2 ticket distribution roster consistent with the user lifecycle.
module User::TicketDistributionMembership
  extend ActiveSupport::Concern

  included do
    has_many :ticket_distribution_members, class_name: 'Ticket::DistributionMember', inverse_of: :user, dependent: :destroy

    association_attributes_ignored :ticket_distribution_members

    validates :discord_uid, format: { with: %r{\A\d+\z} }, allow_blank: true, if: -> { has_attribute?(:discord_uid) }

    before_destroy :ticket_distribution_release_dispatch
  end

  private

  def ticket_distribution_release_dispatch
    Ticket::Distribution::Config.release_dispatch_user!(id)
  end
end
