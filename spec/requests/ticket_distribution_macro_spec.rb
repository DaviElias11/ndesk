# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Ticket distribution macros', :aggregate_failures, db_strategy: :reset, type: :request do
  include_context 'with ticket distribution complexity'

  let(:group)      { create(:group) }
  let(:open_state) { Ticket::State.find_by(name: 'open') }
  # A recent last_login: the first login writes it, and that User event would be in the EventBuffer the examples check.
  let!(:n1)        { create(:ticket_distribution_member, :n1, user: create(:agent, groups: [group], last_login: Time.zone.now)) }
  let!(:n2_a)      { create(:ticket_distribution_member, user: create(:agent, groups: [group])) }
  let!(:n2_b)      { create(:ticket_distribution_member, user: create(:agent, groups: [group])) }
  let!(:ticket)    { create(:ticket, group:, owner: n1.user, state: open_state) }
  let(:filled)     { create(:ticket, group:, owner: n1.user, state: open_state, complexidades: 'moderado') }

  let(:distribution_perform) do
    {
      'distribution.ticket_distribution' => { 'value' => 'handover' },
      'article.note'                     => { 'subject' => 'Repasse', 'body' => 'Realizamos uma análise prévia da sua ocorrência', 'internal' => 'false' },
    }
  end
  let(:macro) { create(:macro, perform: distribution_perform) }

  before { authenticated_as(n1.user) }

  def article_counts
    [ticket, filled].map { |target| Ticket::Article.where(ticket_id: target.id).count }
  end

  describe 'PUT /api/v1/tickets/:id' do
    let(:params) do
      {
        id:                      ticket.id,
        'macro.id'               => macro.id,
        'macro.perform_changes'  => ['distribution.ticket_distribution'],
        article:                 { body: 'Realizamos uma análise prévia', type: 'note', internal: false },
      }
    end

    it 'refuses without complexity and writes nothing' do
      EventBuffer.reset('transaction')

      expect { put "/api/v1/tickets/#{ticket.id}", params:, as: :json }.not_to change(Ticket::Article, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response).to include('error_human'          => 'Fill in the complexity before handing over.',
                                       'unprocessable_entity' => 'ticket_distribution.complexity_missing')
      expect(ticket.reload.owner_id).to eq(n1.user_id)
      expect(EventBuffer.list('transaction')).to be_empty
    end

    it 'hands over to the N2 with the lowest load when the complexity comes in the same submit' do
      create(:ticket, group:, owner: n2_a.user, state: open_state, complexidades: 'moderado')

      put "/api/v1/tickets/#{ticket.id}", params: params.merge(complexidades: 'moderado'), as: :json

      expect(response).to have_http_status(:ok)
      expect(ticket.reload).to have_attributes(owner_id: n2_b.user_id, complexidades: 'moderado')
      expect(n2_b.reload.last_assigned_at).to be_present
      expect(n2_a.reload.last_assigned_at).to be_nil
    end
  end

  describe 'POST /api/v1/tickets/mass_macro' do
    it 'refuses the whole batch before writing anything when a ticket has no complexity' do
      filled
      EventBuffer.reset('transaction')
      allow(Ticket::Distribution::Lock).to receive(:lock_tickets!).and_call_original

      expect { post '/api/v1/tickets/mass_macro', params: { macro_id: macro.id, ticket_ids: [filled.id, ticket.id] }, as: :json }
        .not_to change { article_counts }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response).to include('error'                => 'Fill in the complexity before handing over.',
                                       'error_human'          => 'Fill in the complexity before handing over.',
                                       'unprocessable_entity' => 'ticket_distribution.complexity_missing',
                                       'ticket_ids'           => [ticket.id])
      expect(ticket.reload.owner_id).to eq(n1.user_id)
      expect(filled.reload.owner_id).to eq(n1.user_id)
      expect(n2_a.reload.last_assigned_at).to be_nil
      expect(EventBuffer.list('transaction')).to be_empty
      expect(Ticket::Distribution::Lock).not_to have_received(:lock_tickets!)
    end

    it 'sends tickets with the same load to different N2, the second one seeing the load of the first' do
      ticket.update!(complexidades: 'moderado')

      post '/api/v1/tickets/mass_macro', params: { macro_id: macro.id, ticket_ids: [ticket.id, filled.id] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response['ticket_ids']).to contain_exactly(ticket.id, filled.id)
      expect([ticket.reload.owner_id, filled.reload.owner_id]).to contain_exactly(n2_a.user_id, n2_b.user_id)
      expect(article_counts).to eq([1, 1])
    end

    it 'decides on the state read after the lock, not on the one of the request' do
      other_owner = n2_b.user
      ticket.update!(complexidades: 'moderado')

      allow(Ticket::Distribution::Lock).to receive(:lock_tickets!).and_wrap_original do |original, ids|
        Ticket.where(id: ticket.id).update_all(owner_id: other_owner.id)

        original.call(ids)
      end

      post '/api/v1/tickets/mass_macro', params: { macro_id: macro.id, ticket_ids: [ticket.id] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(ticket.reload.owner_id).to eq(other_owner.id)
      expect(n2_a.reload.last_assigned_at).to be_nil
    end

    it 'refuses before writing anything when a ticket lost its complexity by the time of the lock' do
      ticket.update!(complexidades: 'moderado')
      expect(filled.id).to be > ticket.id # the lock goes by id: the ticket without complexity is the second one to be handled
      EventBuffer.reset('transaction')

      allow(Ticket::Distribution::Lock).to receive(:lock_tickets!).and_wrap_original do |original, ids|
        Ticket.where(id: filled.id).update_all(complexidades: nil)

        original.call(ids)
      end

      expect { post '/api/v1/tickets/mass_macro', params: { macro_id: macro.id, ticket_ids: [ticket.id, filled.id] }, as: :json }
        .not_to change { article_counts }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response).to include('error_human'          => 'Fill in the complexity before handing over.',
                                       'unprocessable_entity' => 'ticket_distribution.complexity_missing',
                                       'ticket_ids'           => [filled.id])
      expect(ticket.reload.owner_id).to eq(n1.user_id)
      expect(filled.reload.owner_id).to eq(n1.user_id)
      expect(n2_a.reload.last_assigned_at).to be_nil
      expect(n2_b.reload.last_assigned_at).to be_nil
      expect(EventBuffer.list('transaction')).to be_empty
    end

    it 'does not refuse a macro that writes the complexity itself' do
      writing_macro = create(:macro, perform: distribution_perform.merge('ticket.complexidades' => { 'value' => 'facil' }))

      post '/api/v1/tickets/mass_macro', params: { macro_id: writing_macro.id, ticket_ids: [ticket.id] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(ticket.reload).to have_attributes(owner_id: n2_a.user_id, complexidades: 'facil')
    end

    it 'refuses a macro that clears the complexity, even of a ticket that has one' do
      filled
      clearing_macro = create(:macro, perform: distribution_perform.merge('ticket.complexidades' => { 'value' => '' }))
      EventBuffer.reset('transaction')

      post '/api/v1/tickets/mass_macro', params: { macro_id: clearing_macro.id, ticket_ids: [filled.id] }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response).to include('ticket_ids' => [filled.id])
      expect(filled.reload).to have_attributes(owner_id: n1.user_id, complexidades: 'moderado')
      expect(EventBuffer.list('transaction')).to be_empty
    end

    it 'does not ask for the complexity in another mode' do
      entry_macro = create(:macro, perform: { 'distribution.ticket_distribution' => { 'value' => 'entry' } })

      post '/api/v1/tickets/mass_macro', params: { macro_id: entry_macro.id, ticket_ids: [ticket.id] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(ticket.reload.owner_id).to eq(n1.user_id)
    end

    it 'does not lock the tickets for a macro without the distribution' do
      other_macro = create(:macro, perform: { 'ticket.title' => { 'value' => 'changed by the macro' } })
      allow(Ticket::Distribution::Lock).to receive(:lock_tickets!).and_call_original

      post '/api/v1/tickets/mass_macro', params: { macro_id: other_macro.id, ticket_ids: [ticket.id] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(ticket.reload.title).to eq('changed by the macro')
      expect(Ticket::Distribution::Lock).not_to have_received(:lock_tickets!)
    end
  end

  describe 'POST /api/v1/tickets/mass_update' do
    it 'does not lock the tickets' do
      allow(Ticket::Distribution::Lock).to receive(:lock_tickets!).and_call_original

      post '/api/v1/tickets/mass_update', params: { attributes: { title: 'changed by the update' }, ticket_ids: [ticket.id] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(ticket.reload.title).to eq('changed by the update')
      expect(Ticket::Distribution::Lock).not_to have_received(:lock_tickets!)
    end
  end
end
