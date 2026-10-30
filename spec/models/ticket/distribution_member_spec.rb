# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::DistributionMember, type: :model do
  let(:agent) { create(:agent) }

  it 'allows the same user once per level', :aggregate_failures do
    create(:ticket_distribution_member, :n1, user: agent)
    expect(build(:ticket_distribution_member, :n1, user: agent)).not_to be_valid
    expect(build(:ticket_distribution_member, user: agent)).to be_valid
  end

  it 'rejects unknown levels' do
    expect(build(:ticket_distribution_member, level: 'n3')).not_to be_valid
  end

  it 'orders by turn: never assigned first, then oldest, then id' do
    newer = create(:ticket_distribution_member, last_assigned_at: 1.hour.ago)
    older = create(:ticket_distribution_member, last_assigned_at: 2.hours.ago)
    never = create(:ticket_distribution_member, last_assigned_at: nil)
    expect(described_class.by_turn).to eq([never, older, newer])
  end

  it 'adds the discord_uid column to users' do
    expect(User.column_names).to include('discord_uid')
  end
end
