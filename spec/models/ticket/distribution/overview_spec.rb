# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::Distribution::Overview, :aggregate_failures, db_strategy: :reset do
  include_context 'with ticket distribution complexity'

  let(:group)      { create(:group) }
  let(:online_ids) { [] }
  let(:ooo_agent)  { create(:agent) }

  def n2_member(user = create(:agent, groups: [group]), **)
    create(:ticket_distribution_member, user:, **)
  end

  def overview
    described_class.new(online_user_ids: online_ids).as_json
  end

  def n2_row(member)
    overview[:n2].find { |row| row[:id] == member.id }
  end

  it 'reads the online users from the sessions by default' do
    member = n2_member
    allow(Sessions).to receive(:list).and_return('1' => { user: { 'id' => member.user_id } })

    row = described_class.new.as_json[:n2].first

    expect(row[:situation]).to eq('in_rotation')
  end

  it 'counts the points and tickets of each N2 from the open tickets' do
    a = n2_member
    b = n2_member
    create(:ticket, owner: a.user, group:, complexidades: 'complexo')
    create(:ticket, owner: a.user, group:, complexidades: 'facil')
    create(:ticket, owner: a.user, group:, complexidades: 'moderado', state: Ticket::State.find_by(name: 'closed'))
    create(:ticket, owner: b.user, group:, complexidades: 'moderado')

    expect(n2_row(a)).to include(points: 7, tickets: 2)
    expect(n2_row(b)).to include(points: 3, tickets: 1)
  end

  describe 'situation' do
    it 'is off when the switch is off, even out of office and offline' do
      member = n2_member(create(:agent, :ooo, ooo_agent:, groups: [group]), active: false)

      expect(n2_row(member)).to include(situation: 'off', active: false)
    end

    it 'is out_of_office with the end date' do
      user   = create(:agent, :ooo, ooo_agent:, groups: [group])
      member = n2_member(user)

      expect(n2_row(member)).to include(situation: 'out_of_office')
      expect(n2_row(member)[:out_of_office_end_at].to_date).to eq(user.out_of_office_end_at.to_date)
    end

    it 'is offline without a session' do
      expect(n2_row(n2_member)).to include(situation: 'offline')
    end

    it 'is in_rotation with a session' do
      member = n2_member
      online = described_class.new(online_user_ids: [member.user_id]).as_json[:n2].first

      expect(online).to include(situation: 'in_rotation')
    end

    it 'puts out_of_office before offline' do
      member = n2_member(create(:agent, :ooo, ooo_agent:, groups: [group]))

      expect(n2_row(member)[:situation]).to eq('out_of_office')
    end
  end

  it 'tells whether the member has a Discord ID' do
    with    = n2_member(create(:agent, groups: [group], discord_uid: '123456'))
    without = n2_member

    expect(n2_row(with)[:discord_uid_present]).to be(true)
    expect(n2_row(without)[:discord_uid_present]).to be(false)
  end

  describe 'problems' do
    let(:dispatch_group) { create(:group) }
    let(:user)           { create(:agent, groups: Group.where(active: true).where.not(id: dispatch_group.id)) }

    before do
      group
      Ticket::Distribution::Config.update!(dispatch_group_id: dispatch_group.id, dispatch_user_id: user.id)
    end

    it 'leaves out the dispatch group for N2' do
      member = n2_member(user)

      expect(n2_row(member)[:problems]).to eq([])
    end

    it 'checks every active group for N1' do
      n1 = create(:ticket_distribution_member, :n1, user: user)

      expect(overview[:n1].find { |row| row[:id] == n1.id }[:problems])
        .to eq([{ type: 'no_group_access', groups: [dispatch_group.name] }])
    end

    it 'checks only the dispatch group for the dispatch owner' do
      expect(overview[:dispatch]).to eq(
        group_id: dispatch_group.id, user_id: user.id,
        problems: [{ type: 'no_group_access', groups: [dispatch_group.name] }]
      )
    end

    it 'has no problems for an unset dispatch owner' do
      Ticket::Distribution::Config.update!(dispatch_user_id: nil)

      expect(overview[:dispatch]).to eq(group_id: dispatch_group.id, user_id: nil, problems: [])
    end
  end

  describe 'preview_user_id' do
    it 'is the N2 with the lowest load, and an agent without any group stays eligible' do
      busy = n2_member
      free = n2_member(create(:agent))
      create(:ticket, owner: busy.user, group:, complexidades: 'complexo')

      expect(overview[:preview_user_id]).to eq(free.user_id)
    end

    it 'is nil without N2' do
      expect(overview[:preview_user_id]).to be_nil
    end
  end

  it 'flags an empty N1' do
    expect(overview[:n1_empty]).to be(true)

    create(:ticket_distribution_member, :n1)

    expect(overview[:n1_empty]).to be(false)
  end

  it 'lists the N1 members' do
    n1 = create(:ticket_distribution_member, :n1)

    expect(overview[:n1]).to contain_exactly(include(id: n1.id, user_id: n1.user_id, name: n1.user.fullname, last_assigned_at: nil))
  end

  it 'alerts when the complexity attribute is missing' do
    expect(overview[:config_alerts]).to eq([])

    Ticket::Distribution::Config.update!(weights: {})
    Setting.set('ticket_distribution', Ticket::Distribution::Config.current.to_h.merge('complexity_attribute' => 'nope'))

    expect(overview[:config_alerts]).to eq(['complexity_attribute_missing'])
  end

  it 'exposes the config and the options' do
    agent = create(:agent, groups: [group])

    expect(overview[:config]).to eq(Ticket::Distribution::Config.current.to_h)
    expect(overview[:options][:agents]).to include(id: agent.id, name: agent.fullname)
    expect(overview[:options][:groups]).to include(include(id: group.id, name: group.name))
    expect(overview[:options][:states]).to include(include(name: 'open'))
    expect(overview[:options][:priorities]).to include(include(name: '2 normal'))
    expect(overview[:options][:complexity_attributes]).to eq(Ticket::Distribution::Config.complexity_attribute_options)
  end
end
