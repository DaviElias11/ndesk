# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Live point calculation: the sum of the complexity weights of the open tickets of each agent, in any group.
class Ticket::Distribution::Load
  CLOSED_STATE_TYPES = %w[closed merged removed].freeze

  def initialize(config)
    @config = config
  end

  # Returns { user_id => { points:, tickets: } } with one entry per requested id. Only tickets with weight > 0 are counted.
  def by_user(user_ids, exclude_ticket_id: nil)
    result = user_ids.index_with { { points: 0, tickets: 0 } }
    attr   = @config.complexity_attribute

    if Ticket.column_names.exclude?(attr)
      Rails.logger.error "Ticket distribution: the complexity attribute '#{attr}' is not a ticket column, the load is counted as 0."
      return result
    end

    unknown = Set.new

    counts(user_ids, attr, exclude_ticket_id).each do |(owner_id, value), amount|
      weight = @config.weight_for(value)
      unknown << value if weight.nil? && value.present?
      next if weight.to_i.zero?

      result[owner_id][:points]  += weight * amount
      result[owner_id][:tickets] += amount
    end

    log_unknown(attr, unknown)

    result
  end

  private

  # attr was checked against Ticket.column_names by the caller, it is never interpolated from anywhere else.
  def counts(user_ids, attr, exclude_ticket_id)
    scope = Ticket
      .where(owner_id: user_ids, state_id: open_state_ids)
      .where.not(state_id: @config.ignored_state_ids)
      .where.not(priority_id: @config.ignored_priority_ids)

    scope = scope.where.not(id: exclude_ticket_id) if exclude_ticket_id

    scope.group(:owner_id, attr).count
  end

  def open_state_ids
    Ticket::State.where.not(state_type_id: Ticket::StateType.where(name: CLOSED_STATE_TYPES).select(:id)).select(:id)
  end

  def log_unknown(attr, values)
    return if values.empty?

    Rails.logger.warn "Ticket distribution: no weight registered for #{attr} value(s) #{values.to_a.sort.join(', ')}, counted as 0."
  end
end
