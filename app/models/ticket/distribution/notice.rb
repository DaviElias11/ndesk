# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Tells the agents that a distribution decision could not be carried out as usual.
#
# Runs in the before_save phase, so the note precedes the macro article: the TransactionDispatcher keeps only the last
# article of a request, and that one must stay the macro article.
module Ticket::Distribution::Notice
  def self.not_handed_over!(ticket:, notify_user_id:)
    as_system do
      create_note(ticket, __('Not handed over: no N2 agent in the rotation.'))

      next if notify_user_id.nil?

      OnlineNotification.add(
        type:          'distribution_not_handed_over',
        object:        'Ticket',
        o_id:          ticket.id,
        seen:          false,
        user_id:       notify_user_id,
        created_by_id: 1,
      )
    end
  end

  def self.no_n1!(ticket:)
    as_system { create_note(ticket, __('No N1 agent can own tickets of this group.')) }

    Rails.logger.warn "No N1 agent can own tickets of group #{ticket.group_id}: ticket #{ticket.id} stays without owner."
  end

  # With a current user, the user columns of every record would be overwritten by it. Without one they stay as given,
  # and the save of the ticket caused by the note keeps the ticket's updated_by_id instead of leaving the system there.
  def self.as_system(&)
    UserInfo.with_user_id(nil, &)
  end
  private_class_method :as_system

  # By ticket_id, not by the record: the callbacks of the article save its ticket, and the record still holds the
  # unsaved changes of the macro.
  def self.create_note(ticket, message)
    Ticket::Article.create!(
      ticket_id:     ticket.id,
      type:          Ticket::Article::Type.lookup(name: 'note'),
      sender:        Ticket::Article::Sender.lookup(name: 'System'),
      content_type:  'text/plain',
      body:          Translation.translate(Setting.get('locale_default') || 'en-us', message),
      internal:      true,
      created_by_id: 1,
      updated_by_id: 1,
    )
  end
  private_class_method :create_note
end
