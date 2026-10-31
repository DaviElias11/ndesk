# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Serializes the distribution decisions until the commit of the chosen owner.
#
# Order of acquisition: ticket rows first (by id, when there are many), advisory lock last. Taking it in any other
# order deadlocks a macro against a bulk macro, which holds several ticket rows in the same transaction.
module Ticket::Distribution::Lock
  KEY = Zlib.crc32('ndesk.ticket_distribution')

  def self.acquire!(ticket_id)
    Ticket.where(id: ticket_id).lock.pluck(:id)
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?)', KEY]))

    nil
  end

  def self.lock_tickets!(ids)
    Ticket.where(id: ids).reorder(:id).lock.to_a
  end
end
