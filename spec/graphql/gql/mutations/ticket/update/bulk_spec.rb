# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Gql::Mutations::Ticket::Update::Bulk, :aggregate_failures, type: :graphql do
  let(:query) do
    <<~QUERY
      mutation ticketUpdateBulk($ticketIds: [ID!]!, $input: TicketUpdateInput!, $macroId: ID) {
        ticketUpdateBulk(ticketIds: $ticketIds, input: $input, macroId: $macroId) {
          success
          errors {
            failedTicket {
              id
            }
            errorType
            message
          }
        }
      }
    QUERY
  end
  let(:agent)           { create(:agent, groups: [ Group.find_by(name: 'Users')]) }
  let(:customer)        { create(:customer) }
  let(:user)            { agent }
  let(:group)           { agent.groups.first }
  let(:ticket1)         { create(:ticket, title: 'Ticket 1', group: agent.groups.first, customer: customer) }
  let(:ticket2)         { create(:ticket, title: 'Ticket 2', group: agent.groups.first, customer: customer) }
  let(:input_payload)   { { title: 'Ticket Bulk Update Mutation Test' } }

  let(:variables) { { ticketIds: [gql.id(ticket1), gql.id(ticket2)], input: input_payload } }

  let(:expected_response) do
    { success: true, errors: nil }.with_indifferent_access
  end

  context 'when updating a ticket' do

    context 'with an agent', authenticated_as: :agent do

      it 'updates the attributes' do
        gql.execute(query, variables: variables)
        expect(gql.result.data).to eq(expected_response)
        expect(ticket1.reload).to have_attributes(title: 'Ticket Bulk Update Mutation Test')
      end

      context 'when a ticket update fails' do
        before do
          allow_any_instance_of(Service::Ticket::Update).to receive(:execute).and_wrap_original do |m, *args, **kwargs|
            if kwargs[:ticket].title == 'Ticket 2'
              raise ActiveRecord::RecordNotSaved.new('test failure during update of second ticket', ticket2)
            end

            m.call(*args, **kwargs)
          end
        end

        let(:expected_response) do
          {
            success: nil,
            errors:  [
              {
                failedTicket: { id: gql.id(ticket2) },
                message:      'test failure during update of second ticket',
                errorType:    ActiveRecord::RecordNotSaved.to_s,
              },
            ],
          }.with_indifferent_access
        end

        it 'rolls back the entire transaction' do
          gql.execute(query, variables: variables)
          expect(gql.result.data).to eq(expected_response)
          expect(ticket1.reload).to have_attributes(title: 'Ticket 1')
        end
      end

      context 'with a macro' do
        let(:new_title) { Faker::Lorem.word }
        let(:macro)     { create(:macro, perform: { 'ticket.title' => { 'value' => new_title } }) }

        let(:variables) do
          {
            ticketIds: [gql.id(ticket1), gql.id(ticket2)],
            input:     input_payload,
            macroId:   gql.id(macro)
          }
        end

        it 'applies the macro' do
          gql.execute(query, variables:)

          expect(ticket1.reload).to have_attributes(title: new_title)
        end
      end

      context 'with a ticket distribution macro', db_strategy: :reset do
        include_context 'with ticket distribution complexity'

        let(:n2_a)    { create(:agent, groups: [group]) }
        let(:n2_b)    { create(:agent, groups: [group]) }
        let(:ticket1) { create(:ticket, group:, customer:, owner: agent, title: 'Ticket 1', complexidades: 'moderado') }
        let(:ticket2) { create(:ticket, group:, customer:, owner: agent, title: 'Ticket 2', complexidades: 'moderado') }

        let(:distribution_perform) do
          {
            'distribution.ticket_distribution' => { 'value' => 'handover' },
            'article.note'                     => { 'subject' => 'Repasse', 'body' => 'Análise prévia', 'internal' => 'false' },
          }
        end
        let(:macro) { create(:macro, perform: distribution_perform) }

        let(:refusal) { 'Fill in the complexity before handing over.' }

        let(:variables) do
          {
            ticketIds: [gql.id(ticket1), gql.id(ticket2)],
            input:     input_payload,
            macroId:   gql.id(macro)
          }
        end

        before do
          create(:ticket_distribution_member, user: n2_a)
          create(:ticket_distribution_member, user: n2_b)
        end

        def complexity_input(value)
          input_payload.merge(objectAttributeValues: [{ name: 'complexidades', value: }])
        end

        def expect_nothing_written
          expect([ticket1.reload, ticket2.reload].map(&:owner_id)).to eq([agent.id, agent.id])
          expect([ticket1, ticket2].map(&:title)).to eq(['Ticket 1', 'Ticket 2'])
          expect(Ticket::Article.where(ticket_id: [ticket1.id, ticket2.id])).to be_empty
          expect(EventBuffer.list('transaction')).to be_empty
        end

        def sql_statements(&)
          statements = []
          subscriber = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] }

          ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &)

          statements
        end

        it 'refuses the whole batch before writing anything when a ticket has no complexity' do
          ticket2.update!(complexidades: nil)
          variables
          EventBuffer.reset('transaction')
          allow(Ticket::Distribution::Lock).to receive(:lock_tickets!).and_call_original

          gql.execute(query, variables:)

          expect(gql.result.data).to eq({
            success: nil,
            errors:  [{ failedTicket: { id: gql.id(ticket2) }, message: refusal, errorType: Ticket::Distribution::ComplexityMissingError.to_s }],
          }.with_indifferent_access)
          expect_nothing_written
          expect(Ticket::Distribution::Lock).not_to have_received(:lock_tickets!)
        end

        it 'refuses before writing anything when a ticket lost its complexity by the time of the lock' do
          variables
          EventBuffer.reset('transaction')

          allow(Ticket::Distribution::Lock).to receive(:lock_tickets!).and_wrap_original do |original, ids|
            Ticket.where(id: ticket2.id).update_all(complexidades: nil)

            original.call(ids)
          end

          gql.execute(query, variables:)

          expect(gql.result.data[:success]).to be_nil
          expect(gql.result.data[:errors].sole).to include(failedTicket: { id: gql.id(ticket2) }, message: refusal)
          expect_nothing_written
        end

        it 'sends the tickets to different N2, the second one seeing the load of the first' do
          gql.execute(query, variables:)

          expect(gql.result.data).to eq(expected_response)
          expect([ticket1.reload.owner_id, ticket2.reload.owner_id]).to contain_exactly(n2_a.id, n2_b.id)
          expect(Ticket::Article.where(ticket_id: ticket1.id).count).to eq(1)
          expect(Ticket::Article.where(ticket_id: ticket2.id).count).to eq(1)
        end

        it 'does not refuse a complexity written by the input of the same mutation' do
          ticket1.update!(complexidades: nil)
          ticket2.update!(complexidades: nil)

          gql.execute(query, variables: variables.merge(input: complexity_input('facil')))

          expect(gql.result.data).to eq(expected_response)
          expect([ticket1.reload.complexidades, ticket2.reload.complexidades]).to eq(%w[facil facil])
          expect([ticket1.owner_id, ticket2.owner_id]).to contain_exactly(n2_a.id, n2_b.id)
        end

        it 'refuses when the input clears the complexity of a ticket that has one' do
          vars = variables.merge(input: complexity_input(''))
          EventBuffer.reset('transaction')

          gql.execute(query, variables: vars)

          expect(gql.result.data[:errors].pluck(:message)).to eq([refusal, refusal])
          expect_nothing_written
        end

        it 'lets what the macro writes win over the input, as the macro runs after it' do
          writing_macro = create(:macro, perform: distribution_perform.merge('ticket.complexidades' => { 'value' => 'facil' }))

          gql.execute(query, variables: variables.merge(input: complexity_input(''), macroId: gql.id(writing_macro)))

          expect(gql.result.data).to eq(expected_response)
          expect([ticket1.reload.complexidades, ticket2.reload.complexidades]).to eq(%w[facil facil])
        end

        it 'locks the rows in order of id, whatever the input order, then the advisory lock, before the first write' do
          allow(Ticket::Distribution::Lock).to receive(:acquire!).and_call_original
          vars = variables.merge(ticketIds: [gql.id(ticket2), gql.id(ticket1)])
          expect(ticket1.id).to be < ticket2.id

          statements = sql_statements { gql.execute(query, variables: vars) }

          expect(gql.result.data).to eq(expected_response)

          row_lock    = statements.index { |sql| sql.match?(%r{ORDER BY "tickets"\."id" ASC.*FOR UPDATE}) }
          advisory    = statements.index { |sql| sql.include?('pg_advisory_xact_lock') }
          first_write = statements.index { |sql| sql.match?(%r{\A\s*(UPDATE|INSERT INTO) }) }

          expect(row_lock).to be_a(Integer)
          expect(row_lock).to be < advisory
          expect(row_lock).to be < first_write

          expect(Ticket::Distribution::Lock).to have_received(:acquire!).with(ticket1.id).ordered
          expect(Ticket::Distribution::Lock).to have_received(:acquire!).with(ticket2.id).ordered
        end

        it 'does not lock nor ask for the complexity with a macro without the distribution' do
          other_macro = create(:macro, perform: { 'ticket.title' => { 'value' => 'changed by the macro' } })
          ticket2.update!(complexidades: nil)
          allow(Ticket::Distribution::Lock).to receive(:lock_tickets!).and_call_original

          gql.execute(query, variables: variables.merge(macroId: gql.id(other_macro)))

          expect(gql.result.data).to eq(expected_response)
          expect(ticket2.reload.title).to eq('changed by the macro')
          expect(Ticket::Distribution::Lock).not_to have_received(:lock_tickets!)
        end

        it 'does not lock nor ask for the complexity without a macro' do
          ticket2.update!(complexidades: nil)
          allow(Ticket::Distribution::Lock).to receive(:lock_tickets!).and_call_original

          gql.execute(query, variables: variables.except(:macroId))

          expect(gql.result.data).to eq(expected_response)
          expect(ticket2.reload.title).to eq('Ticket Bulk Update Mutation Test')
          expect(Ticket::Distribution::Lock).not_to have_received(:lock_tickets!)
        end
      end
    end

    context 'with a customer', authenticated_as: :customer do
      it 'raises an error' do
        gql.execute(query, variables: variables)
        expect(gql.result.error_type).to eq(Exceptions::Forbidden)
      end
    end
  end
end
