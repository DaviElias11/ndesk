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

    it 'rejects a user who is not an active agent' do
      [create(:customer), create(:agent, active: false)].each do |user|
        post '/api/v1/ticket_distribution/members', params: { user_id: user.id, level: 'n2' }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['error']).to eq('Only active agents can be added to the ticket distribution.')
      end
      expect(Ticket::DistributionMember.count).to eq(0)
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

    it 'switches an N2 on with the text true' do
      member = create(:ticket_distribution_member, user: agent, active: false)
      put "/api/v1/ticket_distribution/members/#{member.id}", params: { active: 'true' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(member.reload.active).to be(true)
    end

    it 'rejects a switch value that is not a boolean' do
      member = create(:ticket_distribution_member, user: agent, active: false)

      [{ active: 'qualquer' }, { active: 1 }, {}].each do |params|
        put "/api/v1/ticket_distribution/members/#{member.id}", params:, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['error']).to eq('The switch only accepts true or false.')
      end
      expect(member.reload.active).to be(false)
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

    it 'answers with the stored configuration when the save changes nothing and this process holds older values' do
      Ticket::Distribution::Config.update!(dispatch_group_id: group.id)
      allow(Setting).to receive(:get).and_call_original
      allow(Setting).to receive(:get).with('ticket_distribution').and_return(Ticket::Distribution::Config::DEFAULTS)

      put '/api/v1/ticket_distribution', params: { ignored_state_ids: [] }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response['config']['dispatch_group_id']).to eq(group.id)
    end

    it 'accepts the weights of an attribute without options' do
      put '/api/v1/ticket_distribution', params: { weights: {} }, as: :json

      expect(response).to have_http_status(:ok)
      expect(Setting.get('ticket_distribution')['weights']).to eq({})
    end

    it 'rejects a known key in the wrong format and changes nothing' do
      before = Setting.get('ticket_distribution')

      [{ weights: 'x' }, { weights: [1] }, { ignored_state_ids: '1' }, { complexity_attribute: { name: 'x' } },
       { dispatch_group_id: [group.id] }, { weights: { facil: 2 }, ignored_priority_ids: 'x' }].each do |params|
        put '/api/v1/ticket_distribution', params:, as: :json

        expect(response).to have_http_status(:unprocessable_entity), "#{params.inspect} got #{response.status}"
        expect(json_response['error']).to eq('The ticket distribution configuration has an invalid format.')
      end
      expect(Setting.get('ticket_distribution')).to eq(before)
    end

    it 'rejects a body without any known key' do
      put '/api/v1/ticket_distribution', params: { evil: 'x' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'does not let an unknown key reach the setting' do
      put '/api/v1/ticket_distribution', params: { weights: { facil: 2 }, evil: 'x', admin: true }, as: :json

      expect(response).to have_http_status(:ok)
      expect(Setting.get('ticket_distribution').keys).to match_array(Ticket::Distribution::Config::DEFAULTS.keys)
    end
  end
end
