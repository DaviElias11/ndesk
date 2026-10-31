# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Manage > Ticket Distribution', :aggregate_failures, authenticated_as: :admin, db_strategy: :reset, type: :system do
  include_context 'with ticket distribution complexity'

  let(:group)     { create(:group) }
  let(:admin)     { create(:admin, password: 'test') }
  let(:config)    { Ticket::Distribution::Config.current }
  let!(:n1_agent) { create(:agent, firstname: 'Nina', lastname: 'Entrada', groups: [group], password: 'test') }
  let!(:n2_on)    { create(:agent, firstname: 'Olga', lastname: 'Ligada', groups: [group]) }
  let!(:n2_off)   { create(:agent, firstname: 'Otto', lastname: 'Desligado', groups: [group]) }

  def add_member(level, user)
    find(".js-addMember[data-level='#{level}']").select(user.fullname)

    expect(page).to have_css(member_selector(level, user), text: user.fullname)
  end

  def member_selector(level, user)
    ".js-members[data-level='#{level}'] [data-user-id='#{user.id}']"
  end

  def reload_screen
    visit 'dashboard'
    visit 'manage/ticket_distribution'
    expect(page).to have_css('.ticket-distribution')
  end

  describe 'the rotation' do
    let(:open_state) { Ticket::State.find_by(name: 'open') }
    let!(:ticket)    { create(:ticket, group:, owner: n1_agent, state: open_state, complexidades: 'complexo') }
    let!(:macro) do
      create(:macro,
             name:    'Hand over',
             perform: {
               'distribution.ticket_distribution' => { 'value' => 'handover' },
               'article.note'                     => { 'subject' => 'Handover', 'body' => 'Preliminary analysis done', 'internal' => 'false' },
             })
    end

    it 'is maintained on the screen and its load follows the handover' do
      visit 'manage/ticket_distribution'

      expect(page).to have_css('.alert--danger', text: 'No N1 agent registered')

      add_member('n1', n1_agent)
      add_member('n2', n2_on)
      add_member('n2', n2_off)

      expect(page).to have_no_css('.alert--danger', text: 'No N1 agent registered')

      within(member_selector('n2', n2_off)) { click '.zammad-switch' }

      expect(page).to have_css("#{member_selector('n2', n2_off)} .js-situation", text: 'Switched off')
      expect(page).to have_css("#{member_selector('n2', n2_on)} .js-situation", text: 'Offline · still in rotation')
      expect(page).to have_css('.js-preview', text: "If a handover happened now, it would go to #{n2_on.fullname}")
      expect(page).to have_css("#{member_selector('n2', n2_on)} .js-discord", text: 'No ID')

      logout
      login(username: n1_agent.login, password: 'test')
      visit "ticket/zoom/#{ticket.id}"

      find('.js-openDropdownMacro').click
      find(:macro, macro.id).click

      wait.until { ticket.reload.owner_id == n2_on.id }

      logout
      login(username: admin.login, password: 'test')
      visit 'manage/ticket_distribution'

      expect(page).to have_css("#{member_selector('n2', n2_on)} .js-points", exact_text: '6')
      expect(page).to have_css("#{member_selector('n2', n2_on)} .js-tickets", exact_text: '1')
      expect(page).to have_css("#{member_selector('n2', n2_off)} .js-points", exact_text: '0')

      # Leaving and coming back shows the load of now, not the one of the first visit.
      visit 'dashboard'
      create(:ticket, group:, owner: n2_on, state: open_state, complexidades: 'facil')
      visit 'manage/ticket_distribution'

      expect(page).to have_css("#{member_selector('n2', n2_on)} .js-points", exact_text: '7')
      expect(page).to have_css("#{member_selector('n2', n2_on)} .js-tickets", exact_text: '2')
    end
  end

  it 'does not remove the only N1' do
    create(:ticket_distribution_member, :n1, user: n1_agent)

    visit 'manage/ticket_distribution'

    within(member_selector('n1', n1_agent)) { click '.js-removeMember' }

    expect(page).to have_css('.noty_message', text: 'The last N1 agent cannot be removed.')
    expect(page).to have_css(member_selector('n1', n1_agent), text: n1_agent.fullname)
    expect(Ticket::DistributionMember.n1.pluck(:user_id)).to eq([n1_agent.id])
  end

  it 'removes an N2 and offers the agent again' do
    create(:ticket_distribution_member, user: n2_on)

    visit 'manage/ticket_distribution'

    within(member_selector('n2', n2_on)) { click '.js-removeMember' }

    expect(page).to have_no_css(member_selector('n2', n2_on))
    expect(page).to have_css(".js-addMember[data-level='n2'] option[value='#{n2_on.id}']", visible: :all)
  end

  describe 'the load block' do
    it 'keeps the saved weights and shows 0 for a value without weight' do
      Ticket::Distribution::Config.update!(weights: { 'facil' => 1, 'complexo' => 6 })

      visit 'manage/ticket_distribution'

      expect(find('.js-weight[data-value="moderado"]').value).to eq('0')

      find('.js-weight[data-value="moderado"]').set(4)
      click '.js-saveLoad'

      expect(page).to have_css('.noty_message', text: 'Update successful.')

      reload_screen

      expect(find('.js-weight[data-value="moderado"]').value).to eq('4')
      expect(config.weights).to eq('facil' => 1, 'moderado' => 4, 'complexo' => 6)
    end

    it 'keeps the typed weights and tells why when the save is refused' do
      visit 'manage/ticket_distribution'

      find('.js-weight[data-value="moderado"]').set('')
      click '.js-saveLoad'

      expect(page).to have_css('.noty_message', text: 'Each weight must be an integer greater than or equal to 0.')
      expect(config.weights['moderado']).to eq(3)
    end

    it 'shows the values of the picked attribute and saves their weights', db_strategy: :reset do
      create(:object_manager_attribute_select,
             name:                'esforco',
             display:             'Esforco',
             data_option_options: { 'alto' => 'Alto' },
             screens:             { 'edit' => { 'ticket.agent' => { 'shown' => true, 'required' => false } } })
      ObjectManager::Attribute.migration_execute

      visit 'manage/ticket_distribution'

      find('.js-complexityAttribute').select('Esforco')

      expect(page).to have_no_css('.js-weight[data-value="moderado"]')
      expect(find('.js-weight[data-value="alto"]').value).to eq('0')

      find('.js-weight[data-value="alto"]').set(5)
      click '.js-saveLoad'

      expect(page).to have_css('.noty_message', text: 'Update successful.')
      expect(config).to have_attributes(complexity_attribute: 'esforco', weights: { 'alto' => 5 })
    end

    it 'saves and clears the states and priorities that do not count' do
      closed = Ticket::State.find_by(name: 'closed')
      low    = Ticket::Priority.find_by(name: '1 low')

      visit 'manage/ticket_distribution'

      within('.js-ignoredStates') { find('.js-pool .js-option', text: closed.name).click }
      within('.js-ignoredPriorities') { find('.js-pool .js-option', text: low.name).click }
      click '.js-saveLoad'

      expect(page).to have_css('.noty_message', text: 'Update successful.')
      expect(config.ignored_state_ids).to eq([closed.id])
      expect(config.ignored_priority_ids).to eq([low.id])

      reload_screen

      within('.js-ignoredStates') { find('.js-selected .js-option', text: closed.name).click }
      within('.js-ignoredPriorities') { find('.js-selected .js-option', text: low.name).click }
      click '.js-saveLoad'

      expect(page).to have_css('.noty_message', text: 'Update successful.')
      wait.until { Ticket::Distribution::Config.current.ignored_state_ids.empty? }
      expect(Ticket::Distribution::Config.current.ignored_priority_ids).to eq([])
    end
  end

  describe 'the Disparos block' do
    it 'saves and clears the group and the responsible' do
      visit 'manage/ticket_distribution'

      find('.js-dispatch select[name="dispatch_group_id"]').select(group.name)
      find('.js-dispatch select[name="dispatch_user_id"]').select(n2_on.fullname)
      click '.js-saveDispatch'

      expect(page).to have_css('.noty_message', text: 'Update successful.')
      expect(config).to have_attributes(dispatch_group_id: group.id, dispatch_user_id: n2_on.id)

      reload_screen

      expect(find('.js-dispatch select[name="dispatch_group_id"]').value).to eq(group.id.to_s)
      expect(find('.js-dispatch select[name="dispatch_user_id"]').value).to eq(n2_on.id.to_s)

      find('.js-dispatch select[name="dispatch_user_id"]').select('-')
      click '.js-saveDispatch'

      wait.until { Ticket::Distribution::Config.current.dispatch_user_id.nil? }
      expect(Ticket::Distribution::Config.current.dispatch_group_id).to eq(group.id)
    end

    it 'keeps an inactive group when another field is saved, until the empty option is picked' do
      inactive_group = create(:group, active: false)
      Ticket::Distribution::Config.update!(dispatch_group_id: inactive_group.id)

      visit 'manage/ticket_distribution'

      expect(find('.js-dispatch select[name="dispatch_group_id"]').value).to eq(inactive_group.id.to_s)
      expect(page).to have_select('dispatch_group_id', selected: "Unavailable (ID #{inactive_group.id})")

      find('.js-dispatch select[name="dispatch_user_id"]').select(n2_on.fullname)
      click '.js-saveDispatch'

      wait.until { Ticket::Distribution::Config.current.dispatch_user_id == n2_on.id }
      expect(Ticket::Distribution::Config.current.dispatch_group_id).to eq(inactive_group.id)
      expect(page).to have_select('dispatch_group_id', selected: "Unavailable (ID #{inactive_group.id})")

      find('.js-dispatch select[name="dispatch_group_id"]').select('-')
      click '.js-saveDispatch'

      wait.until { Ticket::Distribution::Config.current.dispatch_group_id.nil? }
      expect(Ticket::Distribution::Config.current.dispatch_user_id).to eq(n2_on.id)
    end

    it 'keeps an inactive responsible when another field is saved' do
      inactive_agent = create(:agent, active: false, groups: [group])
      Ticket::Distribution::Config.update!(dispatch_user_id: inactive_agent.id)

      visit 'manage/ticket_distribution'

      expect(page).to have_select('dispatch_user_id', selected: "Unavailable (ID #{inactive_agent.id})")
      expect(page).to have_css('.js-dispatch .js-problems', text: 'Inactive user')

      find('.js-dispatch select[name="dispatch_group_id"]').select(group.name)
      click '.js-saveDispatch'

      wait.until { Ticket::Distribution::Config.current.dispatch_group_id == group.id }
      expect(Ticket::Distribution::Config.current.dispatch_user_id).to eq(inactive_agent.id)
    end
  end

  describe 'the alerts' do
    let(:unreachable_group) { create(:group, name: '<u>Suporte</u>') }
    let(:evil_agent)        { create(:agent, firstname: '<i>Evil</i>', lastname: 'Agent', groups: [group]) }

    it 'shows the reasons of each member and of the configuration, with the names escaped' do
      unreachable_group
      create(:ticket_distribution_member, user: evil_agent)
      Setting.set('ticket_distribution', config.to_h.merge('complexity_attribute' => 'gone'))

      visit 'manage/ticket_distribution'

      expect(page).to have_css('.js-members[data-level="n2"] td', text: '<i>Evil</i> Agent')
      expect(page).to have_css("#{member_selector('n2', evil_agent)} .js-problems", text: 'No access to: ')
      expect(page).to have_css("#{member_selector('n2', evil_agent)} .js-problems", text: '<u>Suporte</u>')
      expect(page).to have_css('.js-configAlerts .alert--danger', text: 'The complexity attribute is not available')
      expect(page).to have_no_css('.ticket-distribution i', text: 'Evil')
      expect(page).to have_no_css('.ticket-distribution u', text: 'Suporte')
    end

    it 'shows why a member or the Disparos responsible cannot own tickets, and until when one is out of office' do
      inactive      = create(:agent, active: false, groups: [group])
      customer      = create(:customer)
      out_of_office = create(:agent, :ooo, ooo_agent: admin, groups: [group])
      [inactive, customer, out_of_office].each { |user| create(:ticket_distribution_member, user:) }
      Ticket::Distribution::Config.update!(dispatch_group_id: group.id, dispatch_user_id: admin.id)

      visit 'manage/ticket_distribution'

      expect(page).to have_css("#{member_selector('n2', inactive)} .js-problems", text: 'Inactive user')
      expect(page).to have_css("#{member_selector('n2', customer)} .js-problems", text: 'Not an agent (no ticket.agent permission)')
      expect(page).to have_css('.js-dispatch .js-problems', text: "No access to: #{group.name}")
      expect(page).to have_css("#{member_selector('n2', out_of_office)} .js-situation",
                               text: "Out of office until #{out_of_office.out_of_office_end_at.strftime('%m/%d/%Y')}")
    end
  end
end
