# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Creates the ticket attribute used as the complexity source of the ticket distribution.
RSpec.shared_context 'with ticket distribution complexity' do
  before do
    create(:object_manager_attribute_select,
           name:                'complexidades',
           display:             'Complexidades',
           data_option_options: { 'facil' => 'Fácil', 'moderado' => 'Moderado', 'complexo' => 'Complexo' },
           screens:             { 'edit' => { 'ticket.agent' => { 'shown' => true, 'required' => false } } })
    # rubocop:disable Zammad/ExistsDbStrategy -- quem inclui declara db_strategy: :reset
    ObjectManager::Attribute.migration_execute
    # rubocop:enable Zammad/ExistsDbStrategy
  end
end
