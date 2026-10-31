# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# What the bulk macro has to settle around Ticket::PerformChanges::Action::TicketDistribution: the early refusal, before
# any write, and the lock of all its tickets, before the first distribution decision takes the advisory lock.
module Ticket::Distribution::MacroGuard
  ACTION = 'distribution.ticket_distribution'.freeze

  def self.distributes?(macro)
    macro.present? && macro.perform.key?(ACTION)
  end

  # The complexity the macro itself writes replaces the one of the ticket, also when it clears it. So does the one in
  # the input of the same request (the attributes assigned to each ticket before the macro runs), unless the macro writes one.
  def self.tickets_missing_complexity(macro, tickets, input: {})
    return [] if !distributes?(macro) || macro.perform.dig(ACTION, 'value') != 'handover'

    config = Ticket::Distribution::Config.current
    return tickets.to_a if !config.complexity_attribute_present?

    attribute = config.complexity_attribute
    input     = input.to_h.stringify_keys
    written   = macro.perform["ticket.#{attribute}"] || (input.key?(attribute) ? { 'value' => input[attribute] } : nil)

    tickets.select { |ticket| (written ? written['value'] : config.complexity_of(ticket)).blank? }
  end

  # Has to be called inside a transaction. Returns the tickets reloaded, so the decision uses what was read after the lock.
  def self.lock_for(macro, tickets)
    return tickets if !distributes?(macro)

    Ticket::Distribution::Lock.lock_tickets!(tickets.map(&:id))
  end
end
