# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe AddTicketDistributionSetup, :aggregate_failures, type: :db_migration do
  before do
    Setting.where(name: 'ticket_distribution').destroy_all
    Permission.where(name: 'admin.ticket_distribution').destroy_all
    ObjectManager::Attribute.where(name: 'discord_uid').destroy_all
    Trigger.where(name: ['Distribuição — Entrada', 'Distribuição — Reabertura']).destroy_all
  end

  it 'creates permission, setting, the Discord attribute and both triggers switched off' do
    migrate
    expect(Permission.exists?(name: 'admin.ticket_distribution')).to be(true)
    expect(Setting.get('ticket_distribution')).to include('complexity_attribute' => 'complexidades',
                                                          'weights'              => { 'facil' => 1, 'moderado' => 3, 'complexo' => 6 })
    expect(ObjectManager::Attribute.get(object: 'User', name: 'discord_uid')).to be_a(ObjectManager::Attribute)
    entry  = Trigger.find_by(name: 'Distribuição — Entrada')
    reopen = Trigger.find_by(name: 'Distribuição — Reabertura')
    expect([entry.active, reopen.active]).to eq([false, false])
    expect(entry.perform).to eq('distribution.ticket_distribution' => { 'value' => 'entry' })
    expect(reopen.condition['ticket.state_id']).to eq('operator' => 'has changed')
    expect(reopen.perform).to eq('distribution.ticket_distribution' => { 'value' => 'reopening' })
  end
end
