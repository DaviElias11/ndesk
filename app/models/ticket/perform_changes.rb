# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

module Ticket::PerformChanges
  extend ActiveSupport::Concern

  include CanPerformChanges

  included do
    available_perform_change_actions :delete,
                                     :data_privacy_deletion_task,
                                     :attribute_updates,
                                     :notification_email,
                                     :notification_sms,
                                     :notification_webhook,
                                     :article_note,
                                     :ai_agent,
                                     :ticket_distribution
  end

  def pre_execute(perform_changes_data)
    article = begin
      Ticket::Article.find_by(id: perform_changes_data[:context_data].try(:dig, :article_id))
    rescue ArgumentError
      nil
    end

    return if article.nil?

    perform_changes_data[:context_data][:article] = article
  end

  def additional_object_action(object_name, object_key, action_value, _prepared_actions)
    return { name: :ticket_distribution, value: action_value } if object_name == 'distribution' && object_key == 'ticket_distribution'
    return if object_name != 'article'
    return if %w[note].exclude?(object_key)

    { name: :"article_#{object_key.to_sym}", value: action_value }
  end

  private

  # The distribution has to decide on what the other actions of the same perform have set (group, complexity),
  # whatever the order of the keys in the perform hash.
  def execute_before_save(before_save_actions)
    return super if !before_save_actions

    distribution, others = before_save_actions.partition { |action| action.is_a?(Ticket::PerformChanges::Action::TicketDistribution) }

    super(others + distribution)
  end
end
