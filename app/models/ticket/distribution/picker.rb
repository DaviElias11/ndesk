# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# The decision rules of the N1/N2 distribution (entry, handover and reopening). Only reads: returns a Decision.
class Ticket::Distribution::Picker
  def initialize(ticket, config: Ticket::Distribution::Config.current)
    @ticket = ticket
    @config = config
  end

  def entry
    member = Ticket::DistributionMember.n1.by_turn.includes(:user).find do |candidate|
      Ticket::Distribution::Eligibility.can_own?(candidate.user, @ticket.group_id)
    end

    return decision(:assigned, owner_id: member.user_id, member:) if member

    decision(:no_n1, owner_id: 1, notices: [:no_n1])
  end

  def handover(acting_user_id:)
    return decision(:complexity_missing) if @config.complexity_of(@ticket).nil?

    owner = @ticket.owner
    if owner && owner.id != acting_user_id && n2_in_rotation?(owner)
      return decision(:kept, owner_id: owner.id)
    end

    dispatch_or_rotation(exclude_user_id: acting_user_id) ||
      decision(:not_handed_over, notices: [:not_handed_over], notify_user_id: acting_user_id)
  end

  # Only reads, and takes no lock: tells whether #reopening has anything to decide, so the action can skip the locks.
  def reopening?(changes:, author_id:)
    reopened?(changes) && customer_action?(author_id)
  end

  def reopening(changes:, author_id:)
    return decision(:skipped) if !reopening?(changes:, author_id:)

    attended_by = User.find_by(id: changes['owner_id']&.first || @ticket.owner_id)
    if attended_by && may_stay?(attended_by)
      return decision(:kept, owner_id: attended_by.id)
    end

    return entry if @config.complexity_of(@ticket).nil?

    dispatch_or_rotation || not_handed_over_by_entry
  end

  private

  def decision(outcome, **)
    Ticket::Distribution::Decision.new(outcome:, **)
  end

  def dispatch_or_rotation(exclude_user_id: nil)
    dispatch = dispatch_user
    return decision(:dispatch, owner_id: dispatch.id) if dispatch

    member = Ticket::Distribution::Rotation.new(@config).pick(group_id: @ticket.group_id, exclude_user_id:, exclude_ticket_id: @ticket.id)
    decision(:assigned, owner_id: member.user_id, member:) if member
  end

  def dispatch_user
    return if @config.dispatch_group_id.nil? || @config.dispatch_group_id != @ticket.group_id

    user = User.find_by(id: @config.dispatch_user_id)
    user if user && !user.out_of_office? && Ticket::Distribution::Eligibility.can_own?(user, @ticket.group_id)
  end

  def n2_in_rotation?(user)
    Ticket::DistributionMember.n2.switched_on.exists?(user_id: user.id) &&
      !user.out_of_office? &&
      Ticket::Distribution::Eligibility.can_own?(user, @ticket.group_id)
  end

  def may_stay?(user)
    return false if !Ticket::Distribution::Eligibility.can_own?(user, @ticket.group_id)

    Ticket::DistributionMember.n1.exists?(user_id: user.id) ||
      n2_in_rotation?(user) ||
      !Ticket::DistributionMember.exists?(user_id: user.id)
  end

  # Falls back to the entry rule and adds the :not_handed_over notice; the bell goes to the N1 chosen by the entry.
  def not_handed_over_by_entry
    fallback = entry

    decision(
      fallback.outcome,
      owner_id:       fallback.owner_id,
      member:         fallback.member,
      notices:        [:not_handed_over, *fallback.notices],
      notify_user_id: fallback.member&.user_id,
    )
  end

  def reopened?(changes)
    old_id, new_id = changes['state_id']
    return false if old_id.nil? || new_id.nil?

    state_type(old_id) == 'closed' && Ticket::Distribution::Load::CLOSED_STATE_TYPES.exclude?(state_type(new_id))
  end

  # true when the author is a customer-side actor (no ticket.agent and not the system user).
  def customer_action?(author_id)
    return false if author_id == 1

    author = User.find_by(id: author_id)
    !author.nil? && !author.permissions?('ticket.agent')
  end

  def state_type(state_id)
    Ticket::State.find_by(id: state_id)&.state_type&.name
  end
end
