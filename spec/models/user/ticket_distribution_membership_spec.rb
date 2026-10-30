# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe User::TicketDistributionMembership, type: :model do
  let(:agent) { create(:agent) }

  it 'removes the memberships with the user' do
    create(:ticket_distribution_member, :n1, user: agent)
    create(:ticket_distribution_member, user: agent)
    expect { agent.destroy! }.to change(Ticket::DistributionMember, :count).by(-2)
  end

  it 'lets a data privacy task delete a member', :aggregate_failures, performs_jobs: true do
    create(:ticket_distribution_member, user: agent)
    create(:data_privacy_task, deletable: agent)
    DataPrivacyTaskJob.perform_now
    expect(User.exists?(agent.id)).to be(false)
    expect(Ticket::DistributionMember.where(user_id: agent.id)).to be_empty
  end

  it 'clears the dispatch responsible and keeps the dispatch group' do
    group = create(:group)
    Ticket::Distribution::Config.update!(dispatch_group_id: group.id, dispatch_user_id: agent.id)
    agent.destroy!
    config = Ticket::Distribution::Config.current
    expect([config.dispatch_group_id, config.dispatch_user_id]).to eq([group.id, nil])
  end

  it 'keeps the dispatch responsible when another user is destroyed' do
    Ticket::Distribution::Config.update!(dispatch_user_id: agent.id)
    create(:agent).destroy!
    expect(Ticket::Distribution::Config.current.dispatch_user_id).to eq(agent.id)
  end

  it 'accepts only digits as Discord ID', :aggregate_failures do
    expect(build(:agent, discord_uid: '123456789012345678')).to be_valid
    expect(build(:agent, discord_uid: 'abc')).not_to be_valid
    expect(build(:agent, discord_uid: '')).to be_valid
  end

  it 'saves a real Discord ID on an existing user and records history', :aggregate_failures do
    agent.update!(discord_uid: '123456789012345678')

    expect(agent.reload.discord_uid).to eq('123456789012345678')
    expect(History.where(history_object_id: History::Object.find_by(name: 'User').id, o_id: agent.id, value_to: '123456789012345678')).to exist
  end

  it 'does not expose the memberships in the user JSON' do
    create(:ticket_distribution_member, user: agent)
    expect(agent.reload.attributes_with_association_ids).not_to have_key('ticket_distribution_member_ids')
  end

  describe 'API', type: :request do
    let(:admin) { create(:admin) }

    it 'lets an admin set the Discord ID', :aggregate_failures, authenticated_as: :admin do
      put "/api/v1/users/#{agent.id}", params: { discord_uid: '123456789012345678' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(agent.reload.discord_uid).to eq('123456789012345678')
    end
  end
end
