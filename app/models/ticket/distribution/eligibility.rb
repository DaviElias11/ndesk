# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Who can own a ticket. Mirrors Ticket#check_owner_active: active, ticket.agent and full access to the group.
module Ticket::Distribution::Eligibility
  # A nil group_id skips the group test (screen preview).
  def self.can_own?(user, group_id)
    return false if !user.active? || !user.permissions?('ticket.agent')
    return true if group_id.nil?

    user.group_access?(group_id, 'full')
  end

  def self.problems(user, group_ids)
    return [{ type: 'inactive' }] if !user.active?
    return [{ type: 'not_agent' }] if !user.permissions?('ticket.agent')

    names = ::Group.where(id: group_ids).reorder(:name).reject { |group| user.group_access?(group.id, 'full') }.map(&:name)
    return [] if names.empty?

    [{ type: 'no_group_access', groups: names }]
  end
end
