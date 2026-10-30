# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::Distribution::Eligibility, :aggregate_failures do
  let(:suporte) { create(:group, name: 'Suporte') }
  let(:vendas)  { create(:group, name: 'Vendas') }

  let(:cases) do
    {
      'inactive agent'            => [create(:agent, active: false, group_ids_access_map: { suporte.id => 'full' }), false],
      'user without ticket.agent' => [create(:customer), false],
      'agent with read access'    => [create(:agent, group_ids_access_map: { suporte.id => 'read' }), false],
      'agent with full access'    => [create(:agent, group_ids_access_map: { suporte.id => 'full' }), true],
    }
  end

  describe '.can_own?' do
    it 'follows the owner rules of the group' do
      cases.each_value do |(user, expected)|
        expect(described_class.can_own?(user, suporte.id)).to be(expected)
      end
    end

    it 'does not test the group when it is nil' do
      expect(described_class.can_own?(create(:agent), nil)).to be(true)
      expect(described_class.can_own?(create(:agent, active: false), nil)).to be(false)
      expect(described_class.can_own?(create(:customer), nil)).to be(false)
    end

    it 'agrees with Ticket#check_owner_active' do
      cases.each do |label, (user, expected)|
        ticket = create(:ticket, group: suporte, owner: User.find(1))
        ticket.update!(owner: user)

        expect(ticket.reload.owner_id == user.id).to be(expected), "#{label}: expected can_own? #{expected} to match the ticket owner"
        expect(described_class.can_own?(user, suporte.id)).to be(expected)
      end
    end
  end

  describe '.problems' do
    it 'lists the groups the agent cannot own' do
      agent = create(:agent, group_ids_access_map: { vendas.id => 'full', suporte.id => 'read' })

      expect(described_class.problems(agent, [suporte.id, vendas.id])).to eq([{ type: 'no_group_access', groups: ['Suporte'] }])
    end

    it 'reports an inactive user' do
      agent = create(:agent, active: false, group_ids_access_map: { suporte.id => 'full' })

      expect(described_class.problems(agent, [suporte.id])).to eq([{ type: 'inactive' }])
    end

    it 'reports a user that is not an agent' do
      expect(described_class.problems(create(:customer), [suporte.id])).to eq([{ type: 'not_agent' }])
    end

    it 'reports nothing for an eligible agent' do
      agent = create(:agent, group_ids_access_map: { suporte.id => 'full' })

      expect(described_class.problems(agent, [suporte.id])).to eq([])
    end
  end
end
