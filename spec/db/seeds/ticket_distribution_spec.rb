# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Ticket distribution seeds', :aggregate_failures do # rubocop:disable RSpec/DescribeClass
  it 'defines the admin.ticket_distribution permission' do
    expect(Permission.exists?(name: 'admin.ticket_distribution')).to be(true)
  end

  it 'seeds the setting with the default configuration' do
    expect(Setting.get('ticket_distribution')).to include(
      'complexity_attribute' => 'complexidades',
      'weights'              => { 'facil' => 1, 'moderado' => 3, 'complexo' => 6 },
      'ignored_state_ids'    => [],
      'ignored_priority_ids' => [],
      'dispatch_group_id'    => nil,
      'dispatch_user_id'     => nil,
    )
  end

  it 'seeds the Discord ID user attribute' do
    expect(ObjectManager::Attribute.get(object: 'User', name: 'discord_uid')).to be_present
  end

  it 'seeds both distribution triggers switched off' do
    triggers = Trigger.where(name: ['Distribuição — Entrada', 'Distribuição — Reabertura'])

    expect(triggers.count).to eq(2)
    expect(triggers.pluck(:active)).to eq([false, false])
  end

  it 'seeds the distribution triggers with modes the action knows' do
    expect(Trigger.find_by(name: 'Distribuição — Entrada').perform).to eq('distribution.ticket_distribution' => { 'value' => 'entry' })
    expect(Trigger.find_by(name: 'Distribuição — Reabertura').perform).to eq('distribution.ticket_distribution' => { 'value' => 'reopening' })
  end
end
