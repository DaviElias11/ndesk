# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class TicketsMassController < ApplicationController
  include CreatesTicketArticles

  prepend_before_action :authentication_check
  before_action :fetch_tickets

  def macro
    macro = Macro.find params[:macro_id]

    applicable = macro.applicable_on? @tickets

    if !applicable
      render json: {
        error:            __('Macro group restrictions do not cover all tickets'),
        blocking_tickets: applicable.blocking_tickets.map(&:id)
      }, status: :unprocessable_entity

      return
    end

    missing_complexity = Ticket::Distribution::MacroGuard.tickets_missing_complexity(macro, @tickets)

    if missing_complexity.any?
      render_complexity_missing(missing_complexity)

      return
    end

    execute_transaction(@tickets, macro:) do |ticket|
      ticket.screen = 'edit'
      ticket.perform_changes macro, 'macro', nil, current_user.id
    end
  end

  def update
    clean_params = clean_update_params

    execute_transaction(@tickets) do |ticket|
      ticket.update!(clean_params) if clean_params
      if params[:article].present?
        article_create(ticket, params[:article])
      end
    end
  end

  private

  def fetch_tickets
    @tickets = Ticket.find params[:ticket_ids]

    @tickets.each do |elem|
      authorize!(elem, :agent_update_access?)
    end
  rescue Pundit::NotAuthorizedError => e
    render json: { error: true, ticket_id: e.record.id }, status: :unprocessable_entity
  end

  def clean_update_params
    return if params[:attributes].blank?

    clean_params = Ticket.association_name_to_id_convert(params.require(:attributes))
    clean_params = Ticket.param_cleanup(clean_params, true)
    clean_params.compact_blank!

    clean_params[:screen] = 'edit'
    clean_params.delete('number')

    clean_params
  end

  # Refused before the first write, not by the action in the middle of the batch: the rollback would undo the writes of
  # the previous tickets, but their events would stay in the EventBuffer and be dispatched by the next request of the thread.
  def render_complexity_missing(tickets)
    error = Ticket::Distribution::ComplexityMissingError.new

    render json: {
      error:                error.message,
      error_human:          error.message,
      unprocessable_entity: error.entity,
      ticket_ids:           tickets.map(&:id),
    }, status: :unprocessable_entity
  end

  def execute_transaction(tickets, macro: nil, &)
    failed_record = nil

    ActiveRecord::Base.transaction do
      tickets = Ticket::Distribution::MacroGuard.lock_for(macro, tickets)

      # Checked again on what the lock has read, and before the first write. With the rows locked it cannot change anymore.
      missing_complexity = Ticket::Distribution::MacroGuard.tickets_missing_complexity(macro, tickets)

      if missing_complexity.any?
        render_complexity_missing(missing_complexity)

        next
      end

      tickets.each(&)

      assets = ApplicationModel::CanAssets.reduce tickets

      render json: { ticket_ids: tickets.map(&:id), assets: assets }, status: :ok
    rescue => e
      raise e if !e.try(:record)

      failed_record = e.record

      raise ActiveRecord::Rollback
    end

    render json: { error: true, ticket_id: failed_record.id }, status: :unprocessable_entity if failed_record
  end
end
