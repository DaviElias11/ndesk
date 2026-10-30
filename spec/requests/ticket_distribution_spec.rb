# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Ticket distribution API', :aggregate_failures, db_strategy: :reset, type: :request do
  include_context 'with ticket distribution complexity'

  let(:group) { create(:group) }
  let(:admin) { create(:admin) }
  let(:agent) { create(:agent, groups: [group]) }

  describe 'authorization' do
    it 'forbids an agent without the permission' do
      authenticated_as(agent)
      get '/api/v1/ticket_distribution', as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'allows an admin' do
      authenticated_as(admin)
      get '/api/v1/ticket_distribution', as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response).to include('config', 'n1', 'n2', 'dispatch', 'options', 'n1_empty')
    end

    it 'allows an agent whose role has the permission' do
      role = create(:role)
      role.permission_grant('admin.ticket_distribution')
      agent.roles << role

      authenticated_as(agent)
      get '/api/v1/ticket_distribution', as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'members' do
    before { authenticated_as(admin) }

    it 'creates a member and returns the overview' do
      post '/api/v1/ticket_distribution/members', params: { user_id: agent.id, level: 'n2' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response['n2'].pluck('user_id')).to eq([agent.id])
      expect(Ticket::DistributionMember.n2.pluck(:user_id)).to eq([agent.id])
    end

    it 'rejects a duplicate' do
      create(:ticket_distribution_member, user: agent)
      post '/api/v1/ticket_distribution/members', params: { user_id: agent.id, level: 'n2' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'switches an N2 off' do
      member = create(:ticket_distribution_member, user: agent)
      put "/api/v1/ticket_distribution/members/#{member.id}", params: { active: false }, as: :json

      expect(response).to have_http_status(:ok)
      expect(member.reload.active).to be(false)
      expect(json_response['n2'].first['situation']).to eq('off')
    end

    it 'rejects the switch on an N1' do
      member = create(:ticket_distribution_member, :n1, user: agent)
      put "/api/v1/ticket_distribution/members/#{member.id}", params: { active: false }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(member.reload.active).to be(true)
    end

    it 'does not remove the last N1' do
      member = create(:ticket_distribution_member, :n1, user: agent)
      delete "/api/v1/ticket_distribution/members/#{member.id}", as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response['error']).to eq('The last N1 agent cannot be removed.')
      expect(Ticket::DistributionMember.exists?(member.id)).to be(true)
    end

    it 'removes an N1 when there is another one' do
      create(:ticket_distribution_member, :n1)
      member = create(:ticket_distribution_member, :n1, user: agent)
      delete "/api/v1/ticket_distribution/members/#{member.id}", as: :json

      expect(response).to have_http_status(:ok)
      expect(Ticket::DistributionMember.exists?(member.id)).to be(false)
    end

    it 'removes an N2' do
      member = create(:ticket_distribution_member, user: agent)
      delete "/api/v1/ticket_distribution/members/#{member.id}", as: :json

      expect(response).to have_http_status(:ok)
      expect(Ticket::DistributionMember.exists?(member.id)).to be(false)
      expect(json_response['n2']).to eq([])
    end
  end

  describe 'update' do
    before { authenticated_as(admin) }

    it 'rejects an invalid complexity attribute' do
      put '/api/v1/ticket_distribution', params: { complexity_attribute: 'title' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'saves weights, dispatch group and owner' do
      put '/api/v1/ticket_distribution',
          params: { weights: { facil: 2, moderado: 4, complexo: 8 }, dispatch_group_id: group.id, dispatch_user_id: agent.id,
                    ignored_state_ids: [Ticket::State.find_by(name: 'new').id] },
          as:     :json

      expect(response).to have_http_status(:ok)
      expect(Setting.get('ticket_distribution')).to include(
        'weights'           => { 'facil' => 2, 'moderado' => 4, 'complexo' => 8 },
        'dispatch_group_id' => group.id,
        'dispatch_user_id'  => agent.id,
        'ignored_state_ids' => [Ticket::State.find_by(name: 'new').id],
      )
      expect(json_response['config']['weights']).to eq('facil' => 2, 'moderado' => 4, 'complexo' => 8)
    end

    it 'clears an array with an empty list' do
      Ticket::Distribution::Config.update!(ignored_state_ids: [Ticket::State.first.id])
      put '/api/v1/ticket_distribution', params: { ignored_state_ids: [] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(Setting.get('ticket_distribution')['ignored_state_ids']).to eq([])
    end

    it 'does not let an unknown key reach the setting' do
      put '/api/v1/ticket_distribution', params: { weights: { facil: 2 }, evil: 'x', admin: true }, as: :json

      expect(response).to have_http_status(:ok)
      expect(Setting.get('ticket_distribution').keys).to match_array(Ticket::Distribution::Config::DEFAULTS.keys)
    end
  end
end
