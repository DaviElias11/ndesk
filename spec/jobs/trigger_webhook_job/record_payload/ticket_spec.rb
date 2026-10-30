# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'
require 'jobs/trigger_webhook_job/record_payload/base_example'

RSpec.describe TriggerWebhookJob::RecordPayload::Ticket do
  it_behaves_like 'TriggerWebhookJob::RecordPayload backend', :ticket

  describe 'owner payload' do
    subject(:payload) { described_class.new(ticket).generate }

    let(:owner)  { create(:agent, groups: [Group.first]) }
    let(:ticket) { create(:ticket, owner: owner) }

    before do
      owner.update!(discord_uid: '123456789012345678')
      create(:ticket_distribution_member, user: owner)
    end

    it 'carries the Discord ID of the owner' do
      expect(payload['owner']['discord_uid']).to eq('123456789012345678')
    end

    it 'does not carry the distribution memberships of the owner' do
      expect(payload['owner']).not_to have_key('ticket_distribution_member_ids')
    end
  end
end
