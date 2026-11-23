# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::Distribution::Roster, :aggregate_failures do
  let(:agent) { create(:agent) }

  def sql_statements(&)
    statements = []
    subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }

    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &)

    statements
  end

  # The advisory lock before the first write on the lists: what the write reads is already what the decisions see.
  def expect_advisory_lock_before(statements, table_pattern)
    advisory = statements.index { |sql| sql.include?('pg_advisory_xact_lock') }
    write    = statements.index { |sql| sql.match?(table_pattern) }

    expect(advisory).to be_a(Integer)
    expect(write).to be_a(Integer)
    expect(advisory).to be < write
  end

  describe '.add!', current_user_id: 1 do
    it 'adds an active agent' do
      member = described_class.add!(user_id: agent.id, level: 'n2')

      expect(member).to have_attributes(user_id: agent.id, level: 'n2', active: true)
    end

    it 'refuses a customer, an inactive agent and an unknown user' do
      [create(:customer).id, create(:agent, active: false).id, 0].each do |user_id|
        expect { described_class.add!(user_id:, level: 'n1') }
          .to raise_error(Exceptions::UnprocessableEntity, 'Only active agents can be added to the ticket distribution.')
      end
      expect(Ticket::DistributionMember.count).to eq(0)
    end

    it 'writes under the advisory lock' do
      agent
      statements = sql_statements { described_class.add!(user_id: agent.id, level: 'n2') }

      expect_advisory_lock_before(statements, %r{INSERT INTO "ticket_distribution_members"})
    end
  end

  describe '.switch!' do
    let(:member) { create(:ticket_distribution_member, user: agent) }

    it 'switches an N2 off under the advisory lock' do
      member
      statements = sql_statements { described_class.switch!(member.id, active: false) }

      expect(member.reload.active).to be(false)
      expect_advisory_lock_before(statements, %r{UPDATE "ticket_distribution_members"})
    end

    it 'refuses the switch on an N1' do
      n1 = create(:ticket_distribution_member, :n1, user: agent)

      expect { described_class.switch!(n1.id, active: false) }.to raise_error(Exceptions::UnprocessableEntity, 'N1 agents have no switch.')
      expect(n1.reload.active).to be(true)
    end
  end

  describe '.remove!' do
    it 'removes an N1 when there is another one, under the advisory lock' do
      create(:ticket_distribution_member, :n1)
      member     = create(:ticket_distribution_member, :n1, user: agent)
      statements = sql_statements { described_class.remove!(member.id) }

      expect(Ticket::DistributionMember.exists?(member.id)).to be(false)
      expect_advisory_lock_before(statements, %r{SELECT 1 AS one FROM "ticket_distribution_members"})
    end

    it 'refuses to remove the last N1' do
      member = create(:ticket_distribution_member, :n1, user: agent)

      expect { described_class.remove!(member.id) }.to raise_error(Exceptions::UnprocessableEntity, 'The last N1 agent cannot be removed.')
      expect(Ticket::DistributionMember.exists?(member.id)).to be(true)
    end
  end
end
