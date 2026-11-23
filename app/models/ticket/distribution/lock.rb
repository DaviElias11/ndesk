# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Serializes the distribution decisions until the commit of the chosen owner.
#
# Order of acquisition: ticket rows first (by id, when there are many), advisory lock last. Taking it in any other
# order deadlocks a macro against a bulk macro, which holds several ticket rows in the same transaction.
module Ticket::Distribution::Lock
  KEY = Zlib.crc32('ndesk.ticket_distribution')

  # Has to be called inside a transaction: the advisory lock lasts until its commit.
  def self.acquire!(ticket_id)
    Ticket.where(id: ticket_id).lock.pluck(:id)
    advisory_lock!

    nil
  end

  def self.lock_tickets!(ids)
    Ticket.where(id: ids).reorder(:id).lock.to_a
  end

  # For the writes on the N1/N2 lists, which lock no ticket: the block waits for the decision in course, and the next
  # decision waits for its commit, so it reads what the block wrote.
  def self.synchronize
    ActiveRecord::Base.transaction do
      advisory_lock!

      yield
    end
  end

  def self.advisory_lock!
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?)', KEY]))
  end
  private_class_method :advisory_lock!
end
