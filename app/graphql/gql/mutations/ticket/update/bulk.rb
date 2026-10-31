# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Gql::Mutations
  class Ticket::Update::Bulk < BaseMutation
    include Gql::Mutations::Ticket::Concerns::HandlesGroup

    description 'Bulk-update tickets.'

    argument :ticket_ids, [GraphQL::Types::ID], loads: Gql::Types::TicketType, loads_pundit_method: :agent_update_access?, description: 'The tickets to be updated'
    argument :input, Gql::Types::Input::Ticket::UpdateInputType, description: 'The ticket data'
    argument :macro_id, GraphQL::Types::ID, loads: Gql::Types::MacroType, required: false, description: 'The macro to apply onto ticket'

    field :success, Boolean, description: 'Were the tickets updated successfully?'
    # Overwrite the default errors field.
    field :errors, [Gql::Types::Ticket::Update::BulkUserErrorType], description: 'Did the bulk update fail?'

    requires_permission 'ticket.agent'

    def resolve(tickets:, input:, macro: nil)
      return group_has_no_email_error if !group_has_email?(input: input)

      # Refused before the first write, not by the action in the middle of the batch: the rollback would undo the writes of
      # the previous tickets, but their events would stay in the EventBuffer and be dispatched at the end of the request.
      errors = complexity_missing_errors(macro, tickets, input)
      return { errors: } if errors.any?

      execute_transaction(tickets, macro:, input:) do |ticket|
        Service::Ticket::Update
          .new(current_user: context.current_user)
          .execute(ticket: ticket, ticket_data: input, skip_validators: Service::Ticket::Update::Validator.exceptions, macro:)
      end
    end

    def execute_transaction(tickets, macro: nil, input: {}, &)
      errors = nil

      ActiveRecord::Base.transaction do
        tickets = ::Ticket::Distribution::MacroGuard.lock_for(macro, tickets)

        # Checked again on what the lock has read, and before the first write. With the rows locked it cannot change anymore.
        errors = complexity_missing_errors(macro, tickets, input).presence
        next if errors

        tickets.each(&)
      rescue => e
        raise e if !e.try(:record)

        errors = [ { failed_ticket: e.record, message: e.message, error_type: e.class.to_s } ]
        raise ActiveRecord::Rollback
      end

      errors ? { errors: } : { success: true }
    end

    private

    def complexity_missing_errors(macro, tickets, input)
      ::Ticket::Distribution::MacroGuard.tickets_missing_complexity(macro, tickets, input:).map do |ticket|
        error = ::Ticket::Distribution::ComplexityMissingError.new

        { failed_ticket: ticket, message: error.message, error_type: error.class.to_s }
      end
    end
  end
end
