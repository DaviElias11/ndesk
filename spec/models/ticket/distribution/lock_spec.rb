# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::Distribution::Lock, :aggregate_failures do
  let(:ticket) { create(:ticket) }

  def sql_statements(&)
    statements = []
    subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &)

    statements
  end

  describe '.acquire!' do
    it 'holds the advisory lock in the current transaction' do
      ActiveRecord::Base.transaction do
        described_class.acquire!(ticket.id)

        count = ActiveRecord::Base.connection.select_value(<<~SQL.squish)
          SELECT count(*) FROM pg_locks
          WHERE locktype = 'advisory' AND objid = #{described_class::KEY} AND pid = pg_backend_pid()
        SQL

        expect(count).to be >= 1
      end
    end

    it 'locks the ticket row before the advisory lock' do
      ticket

      statements = sql_statements { ActiveRecord::Base.transaction { described_class.acquire!(ticket.id) } }
      row_lock   = statements.index { |sql| sql.match?(%r{FROM "tickets".*FOR UPDATE}) }
      advisory   = statements.index { |sql| sql.include?('pg_advisory_xact_lock') }

      expect(row_lock).to be_a(Integer)
      expect(advisory).to be_a(Integer)
      expect(row_lock).to be < advisory
    end
  end

  describe '.lock_tickets!' do
    it 'returns reloaded tickets, locked in order of id' do
      first  = create(:ticket)
      second = create(:ticket)
      Ticket.where(id: second.id).update_all(title: 'changed elsewhere')

      tickets    = nil
      statements = sql_statements { tickets = described_class.lock_tickets!([second.id, first.id]) }

      expect(tickets).to eq([first, second])
      expect(tickets.last.title).to eq('changed elsewhere')
      expect(statements.grep(%r{ORDER BY "tickets"\."id" ASC.*FOR UPDATE})).not_to be_empty
    end
  end
end
