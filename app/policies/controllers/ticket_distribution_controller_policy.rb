# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Controllers::TicketDistributionControllerPolicy < Controllers::ApplicationControllerPolicy
  default_permit!('admin.ticket_distribution')
end
