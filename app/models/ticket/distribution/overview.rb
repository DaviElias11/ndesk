# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Everything the "Ticket Distribution" admin screen shows: the roster, the live load, the member problems and the preview.
class Ticket::Distribution::Overview
  def initialize(config: Ticket::Distribution::Config.current, online_user_ids: nil)
    @config          = config
    @online_user_ids = online_user_ids
  end

  def as_json(*)
    {
      config:          @config.to_h,
      config_alerts:   config_alerts,
      n1_empty:        n1_members.empty?,
      n1:              n1_members.map { |member| n1_row(member) },
      n2:              n2_members.map { |member| n2_row(member) },
      dispatch:        dispatch,
      preview_user_id: Ticket::Distribution::Rotation.new(@config).pick(group_id: nil)&.user_id,
      options:         options,
    }
  end

  private

  def config_alerts
    @config.complexity_attribute_present? ? [] : ['complexity_attribute_missing']
  end

  def n1_members
    @n1_members ||= Ticket::DistributionMember.n1.by_turn.includes(:user).to_a
  end

  def n2_members
    @n2_members ||= Ticket::DistributionMember.n2.by_turn.includes(:user).to_a
  end

  def n1_row(member)
    {
      id:               member.id,
      user_id:          member.user_id,
      name:             member.user.fullname,
      last_assigned_at: member.last_assigned_at,
      problems:         Ticket::Distribution::Eligibility.problems(member.user, active_group_ids),
    }
  end

  def n2_row(member)
    user = member.user
    load = loads[member.user_id]

    {
      id:                   member.id,
      user_id:              member.user_id,
      name:                 user.fullname,
      active:               member.active,
      situation:            situation(member),
      out_of_office_end_at: user.out_of_office_end_at,
      points:               load[:points],
      tickets:              load[:tickets],
      last_assigned_at:     member.last_assigned_at,
      discord_uid_present:  user.discord_uid.present?,
      problems:             Ticket::Distribution::Eligibility.problems(user, active_group_ids - [@config.dispatch_group_id]),
    }
  end

  # Precedence: off, out_of_office, offline, in_rotation.
  def situation(member)
    return 'off' if !member.active
    return 'out_of_office' if member.user.out_of_office?
    return 'offline' if online_user_ids.exclude?(member.user_id)

    'in_rotation'
  end

  def dispatch
    user = @config.dispatch_user_id && User.find_by(id: @config.dispatch_user_id)

    {
      group_id: @config.dispatch_group_id,
      user_id:  @config.dispatch_user_id,
      problems: user ? Ticket::Distribution::Eligibility.problems(user, [@config.dispatch_group_id].compact) : [],
    }
  end

  def options
    {
      agents:                agents,
      groups:                Group.where(active: true).reorder(:name).map { |group| { id: group.id, name: group.name } },
      states:                Ticket::State.reorder(:name).map { |state| { id: state.id, name: state.name } },
      priorities:            Ticket::Priority.reorder(:name).map { |priority| { id: priority.id, name: priority.name } },
      complexity_attributes: Ticket::Distribution::Config.complexity_attribute_options,
    }
  end

  def agents
    User.with_permissions('ticket.agent').where(active: true).reorder(:firstname, :lastname, :id).map do |user|
      { id: user.id, name: user.fullname }
    end
  end

  def loads
    @loads ||= Ticket::Distribution::Load.new(@config).by_user(n2_members.map(&:user_id))
  end

  def active_group_ids
    @active_group_ids ||= Group.where(active: true).pluck(:id)
  end

  def online_user_ids
    @online_user_ids ||= Sessions.list.values.filter_map { |data| data&.dig(:user, 'id') }
  end
end
