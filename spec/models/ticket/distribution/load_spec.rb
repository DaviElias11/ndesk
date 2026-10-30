# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::Distribution::Load, :aggregate_failures, db_strategy: :reset do
  include_context 'with ticket distribution complexity'

  let(:config) { Ticket::Distribution::Config.current }
  let(:group)  { create(:group) }
  let(:agent)  { create(:agent, groups: [group]) }
  let(:other)  { create(:agent, groups: [group]) }

  def state(name)
    Ticket::State.find_by(name:)
  end

  def by_user(**)
    described_class.new(Ticket::Distribution::Config.current).by_user([agent.id, other.id], **)
  end

  it 'sums the weights of the open tickets of each agent' do
    create(:ticket, owner: agent, group:, complexidades: 'complexo')
    create(:ticket, owner: agent, group:, complexidades: 'facil', state: state('pending reminder'))
    create(:ticket, owner: agent, group:, complexidades: 'moderado', state: state('closed'))
    create(:ticket, owner: agent, group: create(:group), complexidades: 'moderado')
    create(:ticket, owner: agent, group:)

    expect(by_user).to eq(agent.id => { points: 10, tickets: 3 }, other.id => { points: 0, tickets: 0 })
  end

  it 'does not count merged and removed tickets' do
    create(:ticket, owner: agent, group:, complexidades: 'complexo', state: state('merged'))
    create(:ticket, owner: agent, group:, complexidades: 'complexo', state: create(:ticket_state, name: 'Removido', state_type: create(:'ticket/state_type', name: 'removed')))

    expect(by_user[agent.id]).to eq(points: 0, tickets: 0)
  end

  it 'leaves out the ticket being decided' do
    create(:ticket, owner: agent, group:, complexidades: 'complexo')
    excluded = create(:ticket, owner: agent, group:, complexidades: 'moderado')

    expect(by_user(exclude_ticket_id: excluded.id)[agent.id]).to eq(points: 6, tickets: 1)
  end

  context 'with custom states and priorities' do
    let(:melhoria)  { create(:ticket_state, name: 'Melhoria', state_type: Ticket::StateType.find_by(name: 'open')) }
    let(:sem_prev)  { create(:ticket_priority, name: '4 sem previsão') }

    before do
      create(:ticket, owner: agent, group:, complexidades: 'moderado', state: melhoria)
      create(:ticket, owner: agent, group:, complexidades: 'facil', priority: sem_prev)
    end

    it 'weighs them normally by default' do
      expect(by_user[agent.id]).to eq(points: 4, tickets: 2)
    end

    it 'leaves out ignored states and priorities' do
      Ticket::Distribution::Config.update!(ignored_state_ids: [melhoria.id], ignored_priority_ids: [sem_prev.id])

      expect(by_user[agent.id]).to eq(points: 0, tickets: 0)
    end
  end

  it 'weighs a value without registered weight as 0 and logs it once per call' do
    create_list(:ticket, 2, owner: agent, group:, complexidades: 'raro')
    allow(Rails.logger).to receive(:warn)

    expect(by_user[agent.id]).to eq(points: 0, tickets: 0)
    expect(Rails.logger).to have_received(:warn).with(%r{raro}).once
  end

  it 'returns zeros and logs an error when the complexity column does not exist' do
    Setting.set('ticket_distribution', config.to_h.merge('complexity_attribute' => 'nao_existe'))
    create(:ticket, owner: agent, group:, complexidades: 'complexo')
    allow(Rails.logger).to receive(:error)

    expect(by_user).to eq(agent.id => { points: 0, tickets: 0 }, other.id => { points: 0, tickets: 0 })
    expect(Rails.logger).to have_received(:error).with(%r{nao_existe})
  end
end
