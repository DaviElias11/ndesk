# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

# Runs on real commits, with one database connection per thread: the data has to be visible to the threads and the
# locks have to be really contended. So nothing here is rolled back by RSpec: the around below undoes it all.
RSpec.describe 'Ticket distribution concurrency', :aggregate_failures, type: :model do
  self.use_transactional_tests = false

  around do |example|
    setting  = Setting.get(Ticket::Distribution::Config::SETTING)
    baseline = created_models.index_with { |model| model.maximum(:id).to_i }

    begin
      ensure_threads_exited { example.run }
    ensure
      begin
        remove_created_records(baseline)
      ensure
        Setting.set(Ticket::Distribution::Config::SETTING, setting)
        remove_complexity_attribute
        forget_threads_connections
      end
    end
  end

  before do
    create(:object_manager_attribute_select,
           name:                'complexidades',
           display:             'Complexidades',
           data_option_options: { 'facil' => 'Fácil', 'moderado' => 'Moderado', 'complexo' => 'Complexo' },
           screens:             { 'edit' => { 'ticket.agent' => { 'shown' => true, 'required' => false } } })
    ObjectManager::Attribute.migration_execute(false)
  end

  # The seeded group: the factory would also create an e-mail address, and the first one is assigned to the groups.
  let(:group)      { Group.find_by(name: 'Users') }
  let(:open_state) { Ticket::State.find_by(name: 'open') }
  let!(:n1)        { create(:ticket_distribution_member, :n1, user: create(:agent, groups: [group])) }
  let!(:n2_a)      { create(:ticket_distribution_member, user: create(:agent, groups: [group])) }
  let!(:n2_b)      { create(:ticket_distribution_member, user: create(:agent, groups: [group])) }
  let!(:ticket_1)  { create(:ticket, group:, owner: n1.user, state: open_state, complexidades: 'moderado') }
  let!(:ticket_2)  { create(:ticket, group:, owner: n1.user, state: open_state, complexidades: 'moderado') }
  let!(:macro)     { create(:macro, perform: { 'distribution.ticket_distribution' => { 'value' => 'handover' } }) }

  def wait_seconds
    10
  end

  # Everything an example creates has an id above the highest one seen before it. Tickets go first (they take their
  # articles and histories along), the members before their users, and the jobs last, as removing the rest enqueues more.
  # The lookups created on demand (ObjectLookup, History::Type, History::Attribute) stay: any example would recreate them.
  def created_models
    [Ticket, Ticket::Article, History, OnlineNotification, Macro, Ticket::DistributionMember, User, Delayed::Job, ActiveJobLock]
  end

  def remove_created_records(baseline)
    UserInfo.ensure_current_user_id do
      created_models.each do |model|
        model.where('id > ?', baseline[model]).find_each(&:destroy!)
      end
    end

    EventBuffer.reset('transaction')
  end

  def remove_complexity_attribute
    return if !ObjectManager::Attribute.exists?(object_lookup_id: ObjectLookup.by_name('Ticket'), name: 'complexidades')

    ObjectManager::Attribute.remove(object: 'Ticket', name: 'complexidades')
    ObjectManager::Attribute.migration_execute(false)
  end

  # The connections used by the threads hold prepared statements for the tickets table with the column just dropped.
  def forget_threads_connections
    ActiveRecord::Base.connection_pool.flush(0)
  end

  def in_thread
    Thread.new do
      Thread.current.report_on_exception = false

      ActiveRecord::Base.connection_pool.with_connection do
        UserInfo.current_user_id = n1.user_id

        yield
      end
    end
  end

  def apply_macro(ticket)
    ticket.perform_changes(macro, 'macro', nil, n1.user_id)
  end

  # The individual path of the controller: the row of the ticket, then the macro.
  def apply_macro_in_lock(ticket_id)
    ticket = Ticket.find(ticket_id)

    ticket.with_lock do
      yield if block_given?

      apply_macro(ticket)
    end
  end

  # The bulk path of the controller.
  def apply_macro_in_bulk(ticket_ids)
    tickets = ticket_ids.map { |id| Ticket.find(id) }

    ActiveRecord::Base.transaction do
      locked = Ticket::Distribution::MacroGuard.lock_for(macro, tickets)
      yield locked if block_given?

      locked.each { |ticket| apply_macro(ticket) }
    end
  end

  # Holds the threads marked with :hold_in_load just after they read the loads, that is, with the advisory lock taken and
  # the decision not written yet. What the load returns is what a concurrent decision must not get to read as well.
  def hold_in_load(held:, release:)
    allow_any_instance_of(Ticket::Distribution::Load).to receive(:by_user).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap do
        next if !Thread.current[:hold_in_load]

        held << true
        release.pop(timeout: wait_seconds)
      end
    end
  end

  def backend_pid
    ActiveRecord::Base.connection.raw_connection.backend_pid
  end

  def await(queue)
    queue.pop(timeout: wait_seconds) || raise("Nothing arrived in #{wait_seconds} s.")
  end

  # What a connection is waiting for in PostgreSQL: 'advisory' for the advisory lock, 'transactionid' or 'tuple' for the
  # row of a ticket. Ends without an answer as soon as the thread ends: without the locks it never waits for anything.
  def lock_awaited_by(thread, pid)
    deadline = wait_seconds.seconds.from_now

    while thread.alive? && Time.zone.now < deadline
      event = ActiveRecord::Base.connection.select_value(
        "SELECT wait_event FROM pg_stat_activity WHERE pid = #{pid.to_i} AND wait_event_type = 'Lock'"
      )
      return event if event

      sleep 0.01
    end

    nil
  end

  def finish(*threads)
    threads.each do |thread|
      expect(thread.join(wait_seconds)).to eq(thread), "#{thread.inspect} did not end in #{wait_seconds} s."
      thread.value
    end
  end

  it 'makes a handover wait for the commit of the other one, so it sees its load' do
    held    = Queue.new
    release = Queue.new
    pids    = Queue.new

    hold_in_load(held:, release:)

    first = in_thread do
      Thread.current[:hold_in_load] = true
      apply_macro_in_lock(ticket_1.id)
    end
    await(held)

    second = in_thread do
      pids << backend_pid
      apply_macro_in_lock(ticket_2.id)
    end

    expect(lock_awaited_by(second, await(pids))).to eq('advisory')
    expect(second).to be_alive

    release << true
    finish(first, second)

    expect([ticket_1.reload.owner_id, ticket_2.reload.owner_id]).to contain_exactly(n2_a.user_id, n2_b.user_id)
  end

  it 'does not deadlock a bulk macro against a macro on one of its tickets, and the bulk sees the owner written' do
    has_row = Queue.new
    proceed = Queue.new
    pids    = Queue.new
    seen    = Queue.new

    individual = in_thread do
      apply_macro_in_lock(ticket_2.id) do
        has_row << true
        proceed.pop(timeout: wait_seconds)
      end
    end
    await(has_row)

    bulk = in_thread do
      pids << backend_pid
      apply_macro_in_bulk([ticket_1.id, ticket_2.id]) { |locked| seen << locked.to_h { |ticket| [ticket.id, ticket.owner_id] } }
    end

    expect(lock_awaited_by(bulk, await(pids))).to eq('transactionid').or eq('tuple')

    proceed << true
    finish(individual, bulk)

    owner_of_ticket_2 = ticket_2.reload.owner_id
    expect(owner_of_ticket_2).not_to eq(n1.user_id)
    expect(await(seen)[ticket_2.id]).to eq(owner_of_ticket_2)
    expect([ticket_1.reload.owner_id, owner_of_ticket_2]).to contain_exactly(n2_a.user_id, n2_b.user_id)
  end
end
