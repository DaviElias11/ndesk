# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Keeps the N1/N2 ticket distribution roster consistent with the user lifecycle.
module User::TicketDistributionMembership
  extend ActiveSupport::Concern

  included do
    has_many :ticket_distribution_members, class_name: 'Ticket::DistributionMember', inverse_of: :user, dependent: :destroy

    association_attributes_ignored :ticket_distribution_members

    before_validation :ticket_distribution_normalize_discord_uid, if: -> { has_attribute?(:discord_uid) }

    validates :discord_uid, format: { with: %r{\A\d+\z} }, allow_blank: true, if: -> { has_attribute?(:discord_uid) }
    validate :ticket_distribution_discord_uid_of_agent, if: -> { has_attribute?(:discord_uid) && will_save_change_to_discord_uid? }

    before_destroy :ticket_distribution_release_dispatch
  end

  private

  # A value of only spaces would go to the webhook payload as if it were an ID.
  def ticket_distribution_normalize_discord_uid
    self.discord_uid = discord_uid.strip.presence if discord_uid.is_a?(String)
  end

  # The ID is for the mention of the owner on Discord. Checked on the roles in memory: they may come in the same save.
  def ticket_distribution_discord_uid_of_agent
    return if discord_uid.blank?
    return if roles.any? { |role| role.active? && role.with_permission?('ticket.agent') }

    errors.add(:base, __('Only agents can have a Discord ID.'))
  end

  def ticket_distribution_release_dispatch
    Ticket::Distribution::Config.release_dispatch_user!(id)
  end
end
