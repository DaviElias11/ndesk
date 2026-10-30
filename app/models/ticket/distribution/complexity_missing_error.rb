# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Raised when a macro tries to hand a ticket over to the N2 without a complexity. Goes to the client as
# `unprocessable_entity: ENTITY`, so the frontend can tell this error apart from the other save errors.
class Ticket::Distribution::ComplexityMissingError < Exceptions::UnprocessableEntity
  ENTITY = 'ticket_distribution.complexity_missing'.freeze

  def initialize
    super(__('Fill in the complexity before handing over.'), ENTITY)
  end
end
