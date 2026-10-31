# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::Distribution::Picker, :aggregate_failures, db_strategy: :reset do
  include_context 'with ticket distribution complexity'

  let(:group)      { create(:group) }
  let(:config)     { Ticket::Distribution::Config.current }
  let(:substitute) { create(:agent, groups: [group]) }
  let(:n1_user)    { create(:agent, groups: [group]) }
  let(:n2_a_user)  { create(:agent, groups: [group]) }
  let(:n2_b_user)  { create(:agent, groups: [group]) }
  let(:n2_c_user)  { create(:agent, groups: [group]) }
  let!(:n1)        { create(:ticket_distribution_member, :n1, user: n1_user) }
  let!(:n2_a)      { create(:ticket_distribution_member, user: n2_a_user) }
  let!(:n2_b)      { create(:ticket_distribution_member, user: n2_b_user) }
  let!(:n2_c)      { create(:ticket_distribution_member, user: n2_c_user) }
  let(:ticket)     { create(:ticket, group:, owner_id: 1, complexidades: 'moderado') }

  def picker(target = ticket)
    described_class.new(target, config: Ticket::Distribution::Config.current)
  end

  def go_out_of_office(user)
    user.update!(out_of_office: true, out_of_office_start_at: 1.day.ago, out_of_office_end_at: 1.day.from_now, out_of_office_replacement_id: substitute.id)
  end

  def load_for(user, complexity)
    create(:ticket, owner: user, group:, complexidades: complexity)
  end

  describe '#entry' do
    it 'gives the only N1 the ticket even when out of office' do
      go_out_of_office(n1_user)

      decision = picker.entry
      expect(decision.outcome).to eq(:assigned)
      expect(decision.owner_id).to eq(n1_user.id)
      expect(decision.member).to eq(n1)
    end

    it 'uses the N1 turn: nil first, then the oldest, then the lowest id' do
      other = create(:ticket_distribution_member, :n1, user: create(:agent, groups: [group]))
      expect(picker.entry.member).to eq(n1)

      n1.update!(last_assigned_at: 1.hour.ago)
      expect(picker.entry.member).to eq(other)

      other.update!(last_assigned_at: 2.hours.ago)
      expect(picker.entry.member).to eq(other)

      other.update!(last_assigned_at: n1.last_assigned_at)
      expect(picker.entry.member).to eq(n1)
    end

    it 'skips an N1 without access to the group' do
      n1_user.user_groups.destroy_all
      other = create(:ticket_distribution_member, :n1, user: create(:agent, groups: [group]))

      expect(picker.entry.member).to eq(other)
    end

    it 'leaves the ticket without owner when no N1 can own it' do
      n1_user.user_groups.destroy_all

      decision = picker.entry
      expect(decision.outcome).to eq(:no_n1)
      expect(decision.owner_id).to eq(1)
      expect(decision.member).to be_nil
      expect(decision.notices).to eq([:no_n1])
      expect(decision.notify_user_id).to be_nil
    end
  end

  describe '#handover' do
    def handover(acting_user_id: n1_user.id, target: ticket)
      picker(target).handover(acting_user_id:)
    end

    it 'refuses without complexity' do
      ticket.update!(complexidades: nil)

      expect(handover.outcome).to eq(:complexity_missing)
    end

    it 'picks the lowest load' do
      load_for(n2_a_user, 'complexo')
      load_for(n2_b_user, 'moderado')
      load_for(n2_c_user, 'facil')

      decision = handover
      expect(decision.outcome).to eq(:assigned)
      expect(decision.owner_id).to eq(n2_c_user.id)
      expect(decision.member).to eq(n2_c)
    end

    it 'breaks a tie at 0 by last_assigned_at, nil first' do
      n2_a.update!(last_assigned_at: 1.hour.ago)
      n2_b.update!(last_assigned_at: 2.hours.ago)

      expect(handover.member).to eq(n2_c)
    end

    it 'breaks a tie at 0 without nil by the oldest last_assigned_at' do
      n2_a.update!(last_assigned_at: 1.hour.ago)
      n2_b.update!(last_assigned_at: 2.hours.ago)
      n2_c.update!(last_assigned_at: 30.minutes.ago)

      expect(handover.member).to eq(n2_b)
    end

    it 'leaves out switched off and out of office, but keeps offline ones' do
      n2_a.update!(active: false)
      go_out_of_office(n2_b_user)

      expect(handover.member).to eq(n2_c)
    end

    it 'takes the acting user out of the candidates' do
      load_for(n2_a_user, 'complexo')
      load_for(n2_b_user, 'complexo')

      expect(handover(acting_user_id: n2_c_user.id).member).to eq(n2_a)
    end

    it 'keeps an owner who is a switched on N2, without touching the turn' do
      ticket.update!(owner: n2_a_user)

      decision = handover
      expect(decision.outcome).to eq(:kept)
      expect(decision.owner_id).to eq(n2_a_user.id)
      expect(decision.member).to be_nil
      expect(n2_a.reload.last_assigned_at).to be_nil
    end

    it 'does not keep the owner when he applies the handover himself' do
      ticket.update!(owner: n2_a_user)

      decision = handover(acting_user_id: n2_a_user.id)
      expect(decision.outcome).to eq(:assigned)
      expect(decision.owner_id).to be_in([n2_b_user.id, n2_c_user.id])
    end

    context 'with the Disparos group' do
      let(:dispatch_user) { create(:agent, groups: [group]) }

      before do
        Ticket::Distribution::Config.update!(dispatch_group_id: group.id, dispatch_user_id: dispatch_user.id)
      end

      it 'goes to the responsible even with the switch off and without a member' do
        create(:ticket_distribution_member, user: dispatch_user, active: false)

        decision = handover
        expect(decision.outcome).to eq(:dispatch)
        expect(decision.owner_id).to eq(dispatch_user.id)
        expect(decision.member).to be_nil
      end

      it 'falls back to the N2 rule when the responsible is out of office' do
        go_out_of_office(dispatch_user)

        expect(handover.outcome).to eq(:assigned)
      end

      it 'falls back to the N2 rule when the responsible has no access' do
        dispatch_user.user_groups.destroy_all

        expect(handover.outcome).to eq(:assigned)
      end

      it 'falls back to the N2 rule when there is no responsible' do
        Ticket::Distribution::Config.update!(dispatch_user_id: nil)

        expect(handover.outcome).to eq(:assigned)
      end
    end

    it 'does not hand over when everybody is switched off' do
      Ticket::DistributionMember.n2.update_all(active: false)

      decision = handover
      expect(decision.outcome).to eq(:not_handed_over)
      expect(decision.owner_id).to be_nil
      expect(decision.notices).to eq([:not_handed_over])
      expect(decision.notify_user_id).to eq(n1_user.id)
    end

    it 'does not hand over a ticket from a group where no N2 has full access (Review Focus 3)' do
      other_group = create(:group)
      [n2_a_user, n2_b_user, n2_c_user].each { |user| user.user_groups.create!(group: other_group, access: 'read') }
      target = create(:ticket, group: other_group, owner_id: 1, complexidades: 'moderado')

      expect(handover(target:).outcome).to eq(:not_handed_over)
    end

    context 'when the N1 is also an N2 (Review Focus 2)' do
      before { n2_a.update!(user: n1_user) }

      it 'sends the ticket to another N2' do
        ticket.update!(owner: n1_user)

        decision = handover(acting_user_id: n1_user.id)
        expect(decision.outcome).to eq(:assigned)
        expect(decision.owner_id).to be_in([n2_b_user.id, n2_c_user.id])
      end

      it 'does not hand over when he is the only N2' do
        n2_b.destroy!
        n2_c.destroy!
        ticket.update!(owner: n1_user)

        expect(handover(acting_user_id: n1_user.id).outcome).to eq(:not_handed_over)
      end
    end
  end

  describe '#reopening' do
    let(:closed)     { Ticket::State.find_by(name: 'closed') }
    let(:open_state) { Ticket::State.find_by(name: 'open') }
    let(:customer)   { create(:customer) }

    def reopening(changes: { 'state_id' => [closed.id, open_state.id] }, author_id: customer.id, target: ticket)
      picker(target).reopening(changes:, author_id:)
    end

    describe '#reopening?' do
      let(:reopened) { { 'state_id' => [closed.id, open_state.id] } }

      it 'is true only for a closed ticket going to an open state by a customer-side author' do
        expect(picker.reopening?(changes: reopened, author_id: customer.id)).to be(true)
        expect(picker.reopening?(changes: reopened, author_id: n2_b_user.id)).to be(false)
        expect(picker.reopening?(changes: reopened, author_id: 1)).to be(false)
        expect(picker.reopening?(changes: {}, author_id: customer.id)).to be(false)
        expect(picker.reopening?(changes: { 'state_id' => [open_state.id, closed.id] }, author_id: customer.id)).to be(false)
      end
    end

    it 'skips pending action to open' do
      pending_action = Ticket::State.find_by(name: 'pending close')

      expect(reopening(changes: { 'state_id' => [pending_action.id, open_state.id] }).outcome).to eq(:skipped)
    end

    it 'skips closed to merged and to removed' do
      merged  = Ticket::State.find_by(name: 'merged')
      removed = create(:ticket_state, name: 'Removido', state_type: create(:'ticket/state_type', name: 'removed'))

      expect(reopening(changes: { 'state_id' => [closed.id, merged.id] }).outcome).to eq(:skipped)
      expect(reopening(changes: { 'state_id' => [closed.id, removed.id] }).outcome).to eq(:skipped)
    end

    it 'skips without a state change' do
      expect(reopening(changes: {}).outcome).to eq(:skipped)
    end

    it 'skips when the author is an agent' do
      expect(reopening(author_id: n2_b_user.id).outcome).to eq(:skipped)
    end

    it 'skips when the author is user 1' do
      expect(reopening(author_id: 1).outcome).to eq(:skipped)
    end

    it 'keeps the N1 who attended when the follow-up cleared the owner' do
      decision = reopening(changes: { 'state_id' => [closed.id, open_state.id], 'owner_id' => [n1_user.id, 1] })

      expect(decision.outcome).to eq(:kept)
      expect(decision.owner_id).to eq(n1_user.id)
      expect(decision.member).to be_nil
    end

    it 'keeps an owner who is in no list' do
      engineering = create(:agent, groups: [group])
      ticket.update!(owner: engineering)

      decision = reopening
      expect(decision.outcome).to eq(:kept)
      expect(decision.owner_id).to eq(engineering.id)
    end

    it 'keeps a switched on N2 owner' do
      ticket.update!(owner: n2_a_user)

      decision = reopening
      expect(decision.outcome).to eq(:kept)
      expect(decision.owner_id).to eq(n2_a_user.id)
    end

    it 'sends a switched off N2 owner to the lowest load' do
      n2_a.update!(active: false)
      ticket.update!(owner: n2_a_user)
      load_for(n2_b_user, 'complexo')
      load_for(n2_c_user, 'facil')

      decision = reopening
      expect(decision.outcome).to eq(:assigned)
      expect(decision.owner_id).to eq(n2_c_user.id)
      expect(decision.member).to eq(n2_c)
    end

    it 'does not count the ticket being decided against its current owner' do
      n2_a.update!(active: false)
      ticket.update!(owner: n2_c_user, complexidades: 'complexo')
      load_for(n2_b_user, 'moderado')

      decision = reopening(changes: { 'state_id' => [closed.id, open_state.id], 'owner_id' => [n2_a_user.id, n2_c_user.id] })
      expect(decision.outcome).to eq(:assigned)
      expect(decision.owner_id).to eq(n2_c_user.id)
    end

    it 'goes to the entry rule without complexity' do
      n2_a.update!(active: false)
      ticket.update!(owner: n2_a_user, complexidades: nil)

      decision = reopening
      expect(decision.outcome).to eq(:assigned)
      expect(decision.owner_id).to eq(n1_user.id)
      expect(decision.member).to eq(n1)
      expect(decision.notices).to eq([])
    end

    it 'goes to the entry rule without complexity for a Disparos ticket' do
      Ticket::Distribution::Config.update!(dispatch_group_id: group.id, dispatch_user_id: create(:agent, groups: [group]).id)
      n2_a.update!(active: false)
      ticket.update!(owner: n2_a_user, complexidades: nil)

      decision = reopening
      expect(decision.owner_id).to eq(n1_user.id)
      expect(decision.outcome).to eq(:assigned)
    end

    it 'goes to the Disparos responsible without touching the turn' do
      responsible = create(:agent, groups: [group])
      Ticket::Distribution::Config.update!(dispatch_group_id: group.id, dispatch_user_id: responsible.id)
      n2_a.update!(active: false)
      ticket.update!(owner: n2_a_user)

      decision = reopening
      expect(decision.outcome).to eq(:dispatch)
      expect(decision.owner_id).to eq(responsible.id)
      expect(decision.member).to be_nil
    end

    context 'without any N2 in the rotation' do
      before do
        Ticket::DistributionMember.n2.update_all(active: false)
        ticket.update!(owner: n2_a_user)
      end

      it 'falls back to the entry with a notice and a bell for the chosen N1' do
        decision = reopening
        expect(decision.outcome).to eq(:assigned)
        expect(decision.owner_id).to eq(n1_user.id)
        expect(decision.member).to eq(n1)
        expect(decision.notices).to eq([:not_handed_over])
        expect(decision.notify_user_id).to eq(n1_user.id)
      end

      it 'keeps both notices and nobody to notify when there is no N1 either' do
        n1_user.user_groups.destroy_all

        decision = reopening
        expect(decision.owner_id).to eq(1)
        expect(decision.notices).to eq(%i[not_handed_over no_n1])
        expect(decision.notify_user_id).to be_nil
      end
    end
  end
end
