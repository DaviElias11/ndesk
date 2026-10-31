# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Applies the N1/N2 distribution, in macros and triggers. Ticket::PerformChanges runs it after the other before_save
# actions of the same perform, so the decision sees the group and the complexity they have just set.
class Ticket::PerformChanges::Action::TicketDistribution < Ticket::PerformChanges::Action
  MODES = %w[entry handover reopening].freeze

  def self.phase
    :before_save
  end

  def execute(...)
    if MODES.exclude?(mode)
      Rails.logger.error "Unknown ticket distribution mode #{mode.inspect} in #{origin} #{performable.try(:name)}, skipping ticket #{id}."
      return false
    end

    # Once on, the reopening trigger fires on every state change. The locks serialize decisions (spec 5.6): what will
    # decide nothing cannot take them, or a job changing states would make all the others wait until its commit.
    return false if mode == 'reopening' && !picker.reopening?(**reopening_context)

    return distribute_in_savepoint if origin != 'macro'

    refuse_without_complexity!
    distribute
  end

  private

  def mode
    execution_data['value']
  end

  def config
    @config ||= Ticket::Distribution::Config.current
  end

  def picker
    @picker ||= Ticket::Distribution::Picker.new(record, config:)
  end

  def reopening_context
    { changes: context_data.try(:dig, :changes) || {}, author_id: user_id }
  end

  def refuse_without_complexity!
    return if mode != 'handover'
    return if config.complexity_of(record).present?

    raise Ticket::Distribution::ComplexityMissingError
  end

  # A trigger never fails because of the distribution. In the e-mail import the triggers run inside the import
  # transaction: without the savepoint, a PostgreSQL error here would abort it and the import would fail.
  def distribute_in_savepoint
    owner_id_before = record.owner_id

    ActiveRecord::Base.transaction(requires_new: true) { distribute }
  rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout => e
    record.owner_id = owner_id_before
    Rails.logger.error "Ticket #{id} was not distributed by #{origin} #{performable.try(:name)}: #{e.class}: #{e.message}"

    false
  end

  def distribute
    Ticket::Distribution::Lock.acquire!(record.id)

    apply(decision)
  end

  def decision
    case mode
    when 'entry'     then picker.entry
    when 'handover'  then handover
    when 'reopening' then picker.reopening(**reopening_context)
    end
  end

  def handover
    decision = picker.handover(acting_user_id: user_id)
    return decision if decision.outcome != :complexity_missing

    picker.entry
  end

  def apply(decision)
    owner_changed = change_owner(decision.owner_id)

    decision.member&.update!(last_assigned_at: Time.zone.now)
    decision.notices.each { |notice| add_notice(notice, decision) }

    owner_changed
  end

  def change_owner(owner_id)
    return false if owner_id.nil? || owner_id == record.owner_id

    record.history_change_source_attribute(performable, 'owner_id')
    record.owner_id = owner_id

    true
  end

  def add_notice(notice, decision)
    case notice
    when :not_handed_over then Ticket::Distribution::Notice.not_handed_over!(ticket: record, notify_user_id: decision.notify_user_id)
    when :no_n1           then Ticket::Distribution::Notice.no_n1!(ticket: record)
    end
  end
end
