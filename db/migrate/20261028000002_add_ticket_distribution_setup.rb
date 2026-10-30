# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class AddTicketDistributionSetup < ActiveRecord::Migration[8.1]
  def change
    # return if it's a new setup (fresh installs get these via db/seeds)
    return if !Setting.exists?(name: 'system_init_done')

    Permission.create_if_not_exists(
      name:        'admin.ticket_distribution',
      label:       'Ticket Distribution',
      description: 'Manage the N1/N2 ticket distribution.',
      preferences: { prio: 1336 }
    )

    Setting.create_if_not_exists(
      title:       'Ticket distribution',
      name:        'ticket_distribution',
      area:        'Ticket::Distribution',
      description: 'Configuration of the N1/N2 ticket distribution.',
      options:     {},
      state:       {
        'complexity_attribute' => 'complexidades',
        'weights'              => { 'facil' => 1, 'moderado' => 3, 'complexo' => 6 },
        'ignored_state_ids'    => [],
        'ignored_priority_ids' => [],
        'dispatch_group_id'    => nil,
        'dispatch_user_id'     => nil,
      },
      preferences: { permission: ['admin.ticket_distribution'] },
      frontend:    false
    )

    ObjectManager::Attribute.add(
      force:         true,
      object:        'User',
      name:          'discord_uid',
      display:       'Discord ID',
      data_type:     'input',
      data_option:   {
        type:       'text',
        maxlength:  30,
        null:       true,
        item_class: 'formGroup--halfSize',
        permission: ['admin.user'],
      },
      editable:      false,
      active:        true,
      screens:       {
        edit:   { '-all-' => { null: true } },
        create: { '-all-' => { null: true } },
        view:   { '-all-' => { shown: false } },
      },
      to_create:     false,
      to_migrate:    false,
      to_delete:     false,
      position:      1495,
      created_by_id: 1,
      updated_by_id: 1
    )

    Trigger.create_if_not_exists(
      name:                     'Distribuição — Entrada',
      condition:                { 'ticket.action' => { 'operator' => 'is', 'value' => 'create' } },
      perform:                  { 'distribution.ticket_distribution' => { 'value' => 'entry' } },
      activator:                'action',
      execution_condition_mode: 'selective',
      active:                   false,
      created_by_id:            1,
      updated_by_id:            1
    )
    Trigger.create_if_not_exists(
      name:                     'Distribuição — Reabertura',
      condition:                {
        'ticket.action'   => { 'operator' => 'is', 'value' => 'update' },
        'ticket.state_id' => { 'operator' => 'has changed' },
      },
      perform:                  { 'distribution.ticket_distribution' => { 'value' => 'reopening' } },
      activator:                'action',
      execution_condition_mode: 'selective',
      active:                   false,
      created_by_id:            1,
      updated_by_id:            1
    )
  end
end
