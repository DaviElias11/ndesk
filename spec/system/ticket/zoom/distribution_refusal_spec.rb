# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe 'Ticket zoom > Distribution refusal', :aggregate_failures, authenticated_as: :n1_user, db_strategy: :reset, type: :system do
  include_context 'with ticket distribution complexity'

  let(:group)      { create(:group) }
  let(:open_state) { Ticket::State.find_by(name: 'open') }
  let!(:n1)        { create(:ticket_distribution_member, :n1, user: create(:agent, groups: [group])) }
  let(:n1_user)    { n1.user }
  let!(:ticket)    { create(:ticket, group:, owner: n1.user, state: open_state) }
  let!(:macro) do
    create(:macro,
           name:    'Hand over',
           perform: {
             'distribution.ticket_distribution' => { 'value' => 'handover' },
             'article.note'                     => { 'subject' => 'Handover', 'body' => 'Preliminary analysis done', 'internal' => 'false' },
           })
  end

  it 'keeps the refusal notice until it is clicked and does not change the owner' do
    visit "ticket/zoom/#{ticket.id}"

    find('.js-openDropdownMacro').click
    find(:macro, macro.id).click

    expect(page).to have_css('.noty_message', text: 'Fill in the complexity before handing over.')

    sleep 5

    expect(page).to have_css('.noty_message', text: 'Fill in the complexity before handing over.')
    expect(ticket.reload.owner_id).to eq(n1.user_id)

    find('.noty_message', text: 'Fill in the complexity before handing over.').click

    expect(page).to have_no_css('.noty_message', text: 'Fill in the complexity before handing over.')
  end
end
