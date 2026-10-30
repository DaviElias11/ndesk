# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# The N2 rotation: picks the candidate with the lowest load, then the oldest last_assigned_at (nil first), then the lowest id.
class Ticket::Distribution::Rotation
  def initialize(config, load: Ticket::Distribution::Load.new(config))
    @config = config
    @load   = load
  end

  # A nil group_id skips the group test (screen preview).
  def pick(group_id:, exclude_user_id: nil, exclude_ticket_id: nil)
    candidates = Ticket::DistributionMember.n2.switched_on.includes(:user).select do |member|
      member.user_id != exclude_user_id &&
        !member.user.out_of_office? &&
        Ticket::Distribution::Eligibility.can_own?(member.user, group_id)
    end

    return if candidates.empty?

    loads = @load.by_user(candidates.map(&:user_id), exclude_ticket_id:)

    candidates.min_by do |member|
      assigned_at = member.last_assigned_at
      [loads.dig(member.user_id, :points), assigned_at.nil? ? 0 : 1, assigned_at.to_f, member.id]
    end
  end
end
