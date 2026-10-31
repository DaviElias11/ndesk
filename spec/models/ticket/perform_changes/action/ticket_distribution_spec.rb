# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::PerformChanges::Action::TicketDistribution, :aggregate_failures, db_strategy: :reset do
  include_context 'with ticket distribution complexity'

  let(:group)      { create(:group) }
  let(:n1_user)    { create(:agent, groups: [group]) }
  let(:n2_a_user)  { create(:agent, groups: [group]) }
  let(:n2_b_user)  { create(:agent, groups: [group]) }
  let(:n2_c_user)  { create(:agent, groups: [group]) }
  let!(:n1)        { create(:ticket_distribution_member, :n1, user: n1_user) }
  let!(:n2_a)      { create(:ticket_distribution_member, user: n2_a_user) }
  let!(:n2_b)      { create(:ticket_distribution_member, user: n2_b_user) }
  let!(:n2_c)      { create(:ticket_distribution_member, user: n2_c_user) }
  let(:open_state) { Ticket::State.find_by(name: 'open') }
  let(:ticket)     { create(:ticket, group:, owner: n1_user, state: open_state, complexidades: 'moderado') }
  let(:macro)      { create(:macro, perform: { 'distribution.ticket_distribution' => { 'value' => 'handover' } }) }

  before { freeze_time }

  def apply_macro(ticket, macro, agent, body: 'Realizamos uma análise prévia da sua ocorrência')
    ticket.perform_changes(macro, 'macro', nil, agent.id) do |object, _save_needed|
      object.save!
      create(:ticket_article, :outbound_email, ticket: object, body:)
    end
  end

  def switch_on(name)
    Trigger.find_by(name:).tap { |trigger| trigger.update!(active: true) }
  end

  def just_now
    eq(Time.zone.now)
  end

  def internal_notes(target)
    Ticket::Article.where(ticket_id: target.id, internal: true)
  end

  def load_for(user, complexity)
    create(:ticket, owner: user, group:, state: open_state, complexidades: complexity)
  end

  describe 'handover by macro' do
    it 'refuses before any write when complexity is missing' do
      ticket.update!(complexidades: nil)
      EventBuffer.reset('transaction')
      allow(Ticket::Distribution::Lock).to receive(:acquire!).and_call_original

      expect { apply_macro(ticket, macro, n1_user) }
        .to raise_error(Ticket::Distribution::ComplexityMissingError) { |e| expect(e.entity).to eq('ticket_distribution.complexity_missing') }
      expect(EventBuffer.list('transaction')).to be_empty
      expect(Ticket::Distribution::Lock).not_to have_received(:acquire!)
      expect(ticket.reload.owner_id).to eq(n1_user.id)
      expect(n2_a.reload.last_assigned_at).to be_nil
    end

    it 'hands over to the N2 with the lowest load, already reading the complexity filled in the same submit' do
      ticket.update!(complexidades: nil)
      load_for(n2_a_user, 'moderado')
      load_for(n2_c_user, 'facil')

      ticket.assign_attributes(complexidades: 'facil')
      apply_macro(ticket, macro, n1_user)

      expect(ticket.reload.owner_id).to eq(n2_b_user.id)
      expect(n2_b.reload.last_assigned_at).to just_now
      expect(n2_a.reload.last_assigned_at).to be_nil
      expect(n2_c.reload.last_assigned_at).to be_nil
    end

    it 'records no origin in the owner history: the agent who applied the macro shows instead' do
      UserInfo.current_user_id = n1_user.id
      apply_macro(ticket, macro, n1_user)

      history = History.where(o_id: ticket.id, value_to: n2_a_user.fullname).last
      expect(history).to have_attributes(sourceable: nil, created_by_id: n1_user.id)
      expect(ticket.reload.owner_id).to eq(n2_a_user.id)
      expect(n2_a.reload.last_assigned_at).to just_now
    end

    it 'keeps the macro article as the last article when the handover does not happen' do
      Ticket::DistributionMember.n2.update_all(active: false)
      EventBuffer.reset('transaction')
      apply_macro(ticket, macro, n1_user)

      last_article_id = TransactionDispatcher.get_uniq_changes(EventBuffer.list('transaction'))['Ticket'][ticket.id][:article_id]
      expect(Ticket::Article.find(last_article_id).body).to include('análise prévia')

      note = ticket.articles.find_by(internal: true)
      expect(note).to have_attributes(
        created_by_id: 1,
        updated_by_id: 1,
        sender:        Ticket::Article::Sender.lookup(name: 'System'),
        type:          Ticket::Article::Type.lookup(name: 'note'),
        body:          'Not handed over: no N2 agent in the rotation.',
      )
      expect(OnlineNotification.find_by(user_id: n1_user.id, o_id: ticket.id).type_lookup_id)
        .to eq(TypeLookup.by_name('distribution_not_handed_over'))
      expect(ticket.reload.owner_id).to eq(n1_user.id)
      expect(n2_a.reload.last_assigned_at).to be_nil
    end

    it 'keeps the system as the author of the note and the bell during a request of the agent' do
      Ticket::DistributionMember.n2.update_all(active: false)
      UserInfo.current_user_id = n1_user.id

      ticket.perform_changes(macro, 'macro', nil, n1_user.id) { |object, _save_needed| object.save! }

      expect(internal_notes(ticket).last).to have_attributes(created_by_id: 1, updated_by_id: 1)
      expect(OnlineNotification.find_by(user_id: n1_user.id, o_id: ticket.id)).to have_attributes(created_by_id: 1, updated_by_id: 1)
      expect(ticket.reload.updated_by_id).to eq(n1_user.id)
      expect(UserInfo.current_user_id).to eq(n1_user.id)
    end

    it 'does not save the unsaved changes of the macro along with the note' do
      Ticket::DistributionMember.n2.update_all(active: false)
      ticket.assign_attributes(title: 'changed by the macro')

      ticket.perform_changes(macro, 'macro', nil, n1_user.id) do |object, _save_needed|
        expect(object.title_changed?).to be(true)
        expect(Ticket.find(object.id).title).not_to eq('changed by the macro')
        object.save!
      end

      expect(internal_notes(ticket).count).to eq(1)
      expect(ticket.reload.title).to eq('changed by the macro')
    end

    it 'writes the note in the default locale of the system' do
      Ticket::DistributionMember.n2.update_all(active: false)
      Setting.set('locale_default', 'de-de')
      allow(Translation).to receive(:translate).and_call_original

      apply_macro(ticket, macro, n1_user)

      expect(Translation).to have_received(:translate).with('de-de', 'Not handed over: no N2 agent in the rotation.')
    end

    it 'sends the webhook of "ticket updated" with the macro article, not the note', performs_jobs: true do
      webhook_trigger = create(:trigger,
                               condition: { 'ticket.action' => { 'operator' => 'is', 'value' => 'update' } },
                               perform:   { 'notification.webhook' => { 'webhook_id' => create(:webhook).id } })

      Ticket::DistributionMember.n2.update_all(active: false)
      ticket
      EventBuffer.reset('transaction')
      apply_macro(ticket, macro, n1_user)

      macro_article = Ticket::Article.where(ticket_id: ticket.id).reorder(:id).last
      expect(macro_article.body).to include('análise prévia')
      expect(internal_notes(ticket).count).to eq(1)

      expect { TransactionDispatcher.commit }
        .to have_enqueued_job(TriggerWebhookJob).with(webhook_trigger, ticket, macro_article, any_args)
      expect(ticket.reload.owner_id).to eq(n1_user.id)
      expect(n2_a.reload.last_assigned_at).to be_nil
    end

    it 'does not touch the tickets of an N2 switched off, and the next handover goes to another N2 (criterion 3)' do
      own_ticket = load_for(n2_a_user, 'facil')
      other      = create(:ticket, group:, owner: n1_user, state: open_state, complexidades: 'moderado')

      n2_a.update!(active: false)
      apply_macro(ticket, macro, n1_user)

      expect(own_ticket.reload.owner_id).to eq(n2_a_user.id)
      expect(n2_a.reload.last_assigned_at).to be_nil
      expect(ticket.reload.owner_id).to eq(n2_b_user.id)
      expect(n2_b.reload.last_assigned_at).to just_now

      apply_macro(other, macro, n1_user)

      expect(other.reload.owner_id).to eq(n2_c_user.id)
      expect(n2_c.reload.last_assigned_at).to just_now
      expect(n2_a.reload.last_assigned_at).to be_nil
    end

    it 'runs after the other actions, whatever the order of the hash (Review Focus 4)' do
      vendas = create(:group)
      n2_b_user.groups << vendas
      perform = {
        'distribution.ticket_distribution' => { 'value' => 'handover' },
        'ticket.group_id'                  => { 'value' => vendas.id },
      }
      group_macro = create(:macro, perform:)
      expect(group_macro.perform.keys.first).to eq('distribution.ticket_distribution')

      ticket.perform_changes(group_macro, 'macro', nil, n1_user.id)

      ticket.reload
      expect(ticket.group_id).to eq(vendas.id)
      expect(ticket.owner_id).to eq(n2_b_user.id)
      expect(n2_b.reload.last_assigned_at).to just_now
      expect(n2_a.reload.last_assigned_at).to be_nil
    end

    it 'lets a lock failure reach the macro' do
      allow(Ticket::Distribution::Lock).to receive(:acquire!).and_raise(ActiveRecord::Deadlocked)

      expect { apply_macro(ticket, macro, n1_user) }.to raise_error(ActiveRecord::Deadlocked)
      expect(ticket.reload.owner_id).to eq(n1_user.id)
      expect(n2_a.reload.last_assigned_at).to be_nil
    end
  end

  describe 'unknown mode' do
    it 'logs and returns false' do
      allow(Rails.logger).to receive(:error).and_call_original
      action = described_class.new(ticket, { 'value' => 'foo' }, { performable: macro, origin: 'macro', context_data: nil, user_id: n1_user.id })

      expect(action.execute).to be(false)
      expect(Rails.logger).to have_received(:error).with(match(%r{foo}))
      expect(ticket.reload.owner_id).to eq(n1_user.id)
    end
  end

  describe 'entry by trigger' do
    let!(:entry_trigger) { switch_on('Distribuição — Entrada') }
    let(:other_agent)    { create(:agent, groups: [group]) }

    it 'ends with the N1 as owner, even when an agent chose another owner' do
      created = create(:ticket, group:, owner: other_agent, created_by_id: other_agent.id, updated_by_id: other_agent.id)
      TransactionDispatcher.commit

      expect(created.reload.owner_id).to eq(n1_user.id)
      expect(n1.reload.last_assigned_at).to just_now
    end

    it 'records the trigger as the origin of the owner change' do
      created = create(:ticket, group:, owner: other_agent)
      TransactionDispatcher.commit

      expect(History.where(o_id: created.id, value_to: n1_user.fullname).last).to have_attributes(sourceable: entry_trigger)
      expect(created.reload.owner_id).to eq(n1_user.id)
      expect(n1.reload.last_assigned_at).to just_now
    end

    it 'gives the next ticket to the new N1 after the N1 is replaced (criterion 1)' do
      first = create(:ticket, group:, owner: other_agent)
      TransactionDispatcher.commit
      expect(first.reload.owner_id).to eq(n1_user.id)

      new_n1_user = create(:agent, groups: [group])
      n1.destroy!
      new_n1 = create(:ticket_distribution_member, :n1, user: new_n1_user)

      second = create(:ticket, group:, owner: other_agent)
      TransactionDispatcher.commit

      expect(second.reload.owner_id).to eq(new_n1_user.id)
      expect(new_n1.reload.last_assigned_at).to just_now
      expect(first.reload.owner_id).to eq(n1_user.id)
    end

    it 'leaves the ticket without owner and adds a note when no N1 can own it' do
      n1_user.user_groups.destroy_all
      allow(Rails.logger).to receive(:warn).and_call_original

      created = create(:ticket, group:, owner: other_agent)
      TransactionDispatcher.commit

      expect(created.reload.owner_id).to eq(1)
      expect(n1.reload.last_assigned_at).to be_nil
      expect(internal_notes(created).sole).to have_attributes(
        body:          'No N1 agent can own tickets of this group.',
        created_by_id: 1,
        sender:        Ticket::Article::Sender.lookup(name: 'System'),
      )
      expect(Rails.logger).to have_received(:warn).with(match(%r{No N1 agent.*#{created.id}}))
    end
  end

  describe 'order of the triggers (spec 6.2)', performs_jobs: true do
    let(:other_agent) { create(:agent, groups: [group]) }

    def owner_webhook_trigger(name)
      create(:trigger,
             name:,
             condition: {
               'ticket.action'   => { 'operator' => 'is', 'value' => 'create' },
               'ticket.owner_id' => { 'operator' => 'is', 'pre_condition' => 'specific', 'value' => n1_user.id.to_s },
             },
             perform:   { 'notification.webhook' => { 'webhook_id' => create(:webhook).id } })
    end

    before { switch_on('Distribuição — Entrada') }

    it 'fires a webhook conditioned on the owner when it sorts after the entry' do
      webhook_trigger = owner_webhook_trigger('Ticket Criado')
      created = create(:ticket, group:, owner: other_agent)

      expect { TransactionDispatcher.commit }
        .to have_enqueued_job(TriggerWebhookJob).with(webhook_trigger, created, any_args)
      expect(created.reload.owner_id).to eq(n1_user.id)
      expect(n1.reload.last_assigned_at).to just_now
    end

    it 'does not fire the same webhook when it sorts before the entry' do
      owner_webhook_trigger('Aaa — webhook')
      created = create(:ticket, group:, owner: other_agent)

      expect { TransactionDispatcher.commit }.not_to have_enqueued_job(TriggerWebhookJob)
      expect(created.reload.owner_id).to eq(n1_user.id)
      expect(n1.reload.last_assigned_at).to just_now
    end
  end

  describe 'reopening by trigger' do
    let(:customer)     { create(:customer) }
    let(:closed_state) { Ticket::State.find_by(name: 'closed') }
    let(:closed_ticket) do
      create(:ticket, group:, customer:, owner: n2_a_user, state: closed_state, complexidades: 'moderado')
    end

    before do
      switch_on('Distribuição — Reabertura')
      closed_ticket
      TransactionDispatcher.commit
    end

    def reopen(author, **attributes)
      closed_ticket.update!(state: open_state, updated_by_id: author.id, **attributes)
      create(:ticket_article, ticket: closed_ticket, created_by_id: author.id, updated_by_id: author.id)
      TransactionDispatcher.commit
    end

    it 'hands the ticket of a switched-off N2 to the N2 with the lowest load when the customer replies' do
      n2_a.update!(active: false)
      load_for(n2_b_user, 'moderado')
      TransactionDispatcher.commit

      reopen(customer)

      expect(closed_ticket.reload.owner_id).to eq(n2_c_user.id)
      expect(n2_c.reload.last_assigned_at).to just_now
      expect(n2_a.reload.last_assigned_at).to be_nil
    end

    it 'does not change the owner when an agent reopens' do
      n2_a.update!(active: false)

      reopen(n2_b_user)

      expect(closed_ticket.reload.owner_id).to eq(n2_a_user.id)
      expect(n2_b.reload.last_assigned_at).to be_nil
      expect(n2_c.reload.last_assigned_at).to be_nil
    end

    it 'returns the ticket to who attended it when the owner was cleared in the follow-up' do
      reopen(customer, owner_id: 1)

      expect(closed_ticket.reload.owner_id).to eq(n2_a_user.id)
      expect(n2_a.reload.last_assigned_at).to be_nil
    end

    it 'falls back to the entry, with note and bell for the N1, when no N2 is in the rotation' do
      Ticket::DistributionMember.n2.update_all(active: false)

      reopen(customer)

      expect(closed_ticket.reload.owner_id).to eq(n1_user.id)
      expect(n1.reload.last_assigned_at).to just_now
      expect(internal_notes(closed_ticket).sole.body).to eq('Not handed over: no N2 agent in the rotation.')
      expect(OnlineNotification.find_by(user_id: n1_user.id, o_id: closed_ticket.id).type_lookup_id)
        .to eq(TypeLookup.by_name('distribution_not_handed_over'))
    end

    it 'adds both notes and no bell when neither N2 nor N1 can receive' do
      Ticket::DistributionMember.n2.update_all(active: false)
      n1_user.user_groups.destroy_all

      reopen(customer)

      expect(closed_ticket.reload.owner_id).to eq(1)
      expect(n1.reload.last_assigned_at).to be_nil
      expect(internal_notes(closed_ticket).pluck(:body)).to contain_exactly(
        'Not handed over: no N2 agent in the rotation.',
        'No N1 agent can own tickets of this group.',
      )
      expect(OnlineNotification.where(o_id: closed_ticket.id, type_lookup_id: TypeLookup.by_name('distribution_not_handed_over'))).to be_empty
    end

    describe 'the locks (spec 5.6)' do
      before { allow(Ticket::Distribution::Lock).to receive(:acquire!).and_call_original }

      it 'takes no lock when an agent reopens' do
        reopen(n2_b_user)

        expect(Ticket::Distribution::Lock).not_to have_received(:acquire!)
        expect(closed_ticket.reload.owner_id).to eq(n2_a_user.id)
      end

      it 'takes no lock when an agent closes a ticket' do
        ticket = create(:ticket, group:, customer:, owner: n2_a_user, state: open_state, complexidades: 'moderado')
        TransactionDispatcher.commit

        ticket.update!(state: closed_state, updated_by_id: n2_b_user.id)
        TransactionDispatcher.commit

        expect(Ticket::Distribution::Lock).not_to have_received(:acquire!)
        expect(ticket.reload.owner_id).to eq(n2_a_user.id)
      end

      it 'takes no lock when the system changes the state of a closed ticket, as a job does' do
        reopen(User.find(1))

        expect(Ticket::Distribution::Lock).not_to have_received(:acquire!)
        expect(closed_ticket.reload.owner_id).to eq(n2_a_user.id)
      end

      it 'takes no lock when a customer moves a ticket that was not closed to open' do
        pending_state = Ticket::State.find_by(name: 'pending reminder')
        ticket        = create(:ticket, group:, customer:, owner: n2_a_user, state: pending_state, pending_time: 1.day.from_now, complexidades: 'moderado')
        TransactionDispatcher.commit

        ticket.update!(state: open_state, updated_by_id: customer.id)
        TransactionDispatcher.commit

        expect(Ticket::Distribution::Lock).not_to have_received(:acquire!)
        expect(ticket.reload.owner_id).to eq(n2_a_user.id)
      end

      it 'locks and distributes when a customer really reopens' do
        n2_a.update!(active: false)

        reopen(customer)

        expect(Ticket::Distribution::Lock).to have_received(:acquire!).with(closed_ticket.id).once
        expect(closed_ticket.reload.owner_id).to eq(n2_b_user.id)
        expect(n2_b.reload.last_assigned_at).to just_now
      end
    end
  end

  describe 'handover by trigger' do
    let(:handover_trigger) do
      create(:trigger,
             condition: { 'ticket.action' => { 'operator' => 'is', 'value' => 'create' } },
             perform:   { 'distribution.ticket_distribution' => { 'value' => 'handover' } })
    end

    it 'falls back to the entry and raises nothing without complexity' do
      handover_trigger
      created = create(:ticket, group:, owner: n2_a_user, complexidades: nil)
      allow(Rails.logger).to receive(:error).and_call_original

      TransactionDispatcher.commit

      expect(Rails.logger).not_to have_received(:error)
      expect(created.reload.owner_id).to eq(n1_user.id)
      expect(n1.reload.last_assigned_at).to just_now
      expect(n2_a.reload.last_assigned_at).to be_nil
    end

    it 'does not raise when called directly either' do
      created = create(:ticket, group:, owner: n2_a_user, complexidades: nil)

      expect { created.perform_changes(handover_trigger, 'trigger', nil, n2_a_user.id) }.not_to raise_error
      expect(created.reload.owner_id).to eq(n1_user.id)
      expect(n1.reload.last_assigned_at).to just_now
    end
  end

  describe 'lock failure by trigger' do
    let(:entry_trigger) { Trigger.find_by(name: 'Distribuição — Entrada') }
    let(:other_agent)   { create(:agent, groups: [group]) }
    let(:created)       { create(:ticket, group:, owner: other_agent) }

    before { allow(Rails.logger).to receive(:error).and_call_original }

    [ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout].each do |error|
      it "logs #{error} and does not distribute" do
        allow(Ticket::Distribution::Lock).to receive(:acquire!).and_raise(error)

        expect { created.perform_changes(entry_trigger, 'trigger', nil, other_agent.id) }.not_to raise_error

        expect(Rails.logger).to have_received(:error).with(match(%r{#{created.id}}))
        expect(created.reload.owner_id).to eq(other_agent.id)
        expect(n1.reload.last_assigned_at).to be_nil
      end
    end

    it 'does not leave the chosen owner in memory when the failure comes after it was written' do
      n1_user.user_groups.destroy_all
      allow(Ticket::Distribution::Notice).to receive(:no_n1!).and_raise(ActiveRecord::Deadlocked)

      expect { created.perform_changes(entry_trigger, 'trigger', nil, other_agent.id) }.not_to raise_error

      expect(created.owner_id).to eq(other_agent.id)
      expect(created).not_to be_changed
      expect(created.reload.owner_id).to eq(other_agent.id)
    end

    it 'does not abort the surrounding transaction on a real lock timeout (e-mail import)' do
      connection = ActiveRecord::Base.connection
      created

      holder = PG.connect(connection.raw_connection.conninfo_hash.slice(:host, :port, :user, :password, :dbname).compact)
      holder.exec("SELECT pg_advisory_lock(#{Ticket::Distribution::Lock::KEY})")

      begin
        ActiveRecord::Base.transaction do
          connection.execute("SET LOCAL lock_timeout = '100ms'")

          expect { created.perform_changes(entry_trigger, 'trigger', nil, other_agent.id) }.not_to raise_error

          expect(Ticket.find(created.id).owner_id).to eq(other_agent.id)
        end
      ensure
        holder.close
      end

      expect(Rails.logger).to have_received(:error).with(match(%r{#{created.id}}))
      expect(n1.reload.last_assigned_at).to be_nil
    end
  end
end
