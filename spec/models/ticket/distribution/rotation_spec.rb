# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::Distribution::Rotation, :aggregate_failures, db_strategy: :reset do
  include_context 'with ticket distribution complexity'

  let(:group)    { create(:group) }
  let(:rotation) { described_class.new(Ticket::Distribution::Config.current) }

  def member_for(**)
    create(:ticket_distribution_member, user: create(:agent, groups: [group]), **)
  end

  it 'picks the lowest load' do
    a = member_for
    b = member_for
    c = member_for
    create(:ticket, owner: a.user, group:, complexidades: 'complexo')
    create(:ticket, owner: b.user, group:, complexidades: 'moderado')
    create(:ticket, owner: c.user, group:, complexidades: 'facil')

    expect(rotation.pick(group_id: group.id)).to eq(c)
  end

  it 'leaves out the ticket being decided from the load' do
    a = member_for
    b = member_for
    ticket = create(:ticket, owner: a.user, group:, complexidades: 'complexo')
    create(:ticket, owner: b.user, group:, complexidades: 'moderado')

    expect(rotation.pick(group_id: group.id)).to eq(b)
    expect(rotation.pick(group_id: group.id, exclude_ticket_id: ticket.id)).to eq(a)
  end

  it 'breaks ties by the oldest last_assigned_at, nil first, then by member id' do
    recent = member_for(last_assigned_at: 1.hour.ago)
    old    = member_for(last_assigned_at: 2.hours.ago)
    never  = member_for

    expect(rotation.pick(group_id: group.id)).to eq(never)

    never.destroy!
    expect(rotation.pick(group_id: group.id)).to eq(old)

    old.update!(last_assigned_at: recent.last_assigned_at)
    expect(rotation.pick(group_id: group.id)).to eq(recent)
  end

  it 'skips switched off, out of office, excluded and non N2 members' do
    member_for(active: false)
    member_for.user.update!(out_of_office: true, out_of_office_start_at: 1.day.ago, out_of_office_end_at: 1.day.from_now, out_of_office_replacement_id: 1)
    excluded = member_for
    member_for(level: 'n1')
    ok = member_for

    expect(rotation.pick(group_id: group.id, exclude_user_id: excluded.user_id)).to eq(ok)
  end

  it 'skips members without full access to the group' do
    create(:ticket_distribution_member, user: create(:agent, groups: [create(:group)]))

    expect(rotation.pick(group_id: group.id)).to be_nil
  end

  it 'keeps a member without access to any group as candidate when group_id is nil' do
    member = create(:ticket_distribution_member, user: create(:agent))

    expect(rotation.pick(group_id: nil)).to eq(member)
  end

  it 'returns nil without candidates' do
    expect(rotation.pick(group_id: group.id)).to be_nil
  end
end
