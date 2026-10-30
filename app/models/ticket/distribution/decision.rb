# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# What the distribution decided for a ticket. Pure data: whoever applies it does the writes.
#
# - outcome:        :assigned, :dispatch, :kept, :no_n1, :not_handed_over, :complexity_missing or :skipped
# - owner_id:       owner to write (nil = leave as is)
# - member:         member whose last_assigned_at must be updated (nil = none)
# - notices:        :not_handed_over and/or :no_n1 (empty = no internal note)
# - notify_user_id: who gets the bell notification of :not_handed_over (nil = nobody)
Ticket::Distribution::Decision = Data.define(:outcome, :owner_id, :member, :notices, :notify_user_id) do
  def initialize(outcome:, owner_id: nil, member: nil, notices: [], notify_user_id: nil)
    super
  end
end
