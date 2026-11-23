# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# The writes of the screen on the N1/N2 lists. Each one runs under Lock.synchronize: when it returns, no decision in
# course still sees the lists of before it, and two writes do not check the lists at the same time.
module Ticket::Distribution::Roster
  def self.add!(user_id:, level:)
    user = ::User.find_by(id: user_id)
    if !user || !Ticket::Distribution::Eligibility.can_own?(user, nil)
      raise Exceptions::UnprocessableEntity, __('Only active agents can be added to the ticket distribution.')
    end

    Ticket::Distribution::Lock.synchronize { Ticket::DistributionMember.create!(user:, level:) }
  end

  def self.switch!(member_id, active:)
    Ticket::Distribution::Lock.synchronize do
      member = Ticket::DistributionMember.find(member_id)
      raise Exceptions::UnprocessableEntity, __('N1 agents have no switch.') if member.level == 'n1'

      member.update!(active:)
    end
  end

  def self.remove!(member_id)
    Ticket::Distribution::Lock.synchronize do
      member = Ticket::DistributionMember.find(member_id)

      if member.level == 'n1' && Ticket::DistributionMember.n1.where.not(id: member.id).none?
        raise Exceptions::UnprocessableEntity, __('The last N1 agent cannot be removed.')
      end

      member.destroy!
    end
  end
end
