# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

RSpec.describe Ticket::Distribution::Config, :aggregate_failures do
  let(:config) { described_class.current }

  describe 'defaults' do
    it 'reads the seeded defaults' do
      expect(config).to have_attributes(
        complexity_attribute: 'complexidades',
        weights:              { 'facil' => 1, 'moderado' => 3, 'complexo' => 6 },
        ignored_state_ids:    [],
        ignored_priority_ids: [],
        dispatch_group_id:    nil,
        dispatch_user_id:     nil,
      )
    end

    it 'falls back to the default for a missing key' do
      Setting.set('ticket_distribution', { 'complexity_attribute' => 'other' })

      expect(config).to have_attributes(complexity_attribute: 'other', weights: { 'facil' => 1, 'moderado' => 3, 'complexo' => 6 })
    end
  end

  describe '#weight_for' do
    it 'returns the weight of a value' do
      expect(config.weight_for('moderado')).to eq(3)
    end

    it 'returns nil for a value without weight' do
      expect(config.weight_for('raro')).to be_nil
    end
  end

  context 'without the complexity attribute' do
    it 'reports it as absent and reads no complexity' do
      expect(config.complexity_attribute_present?).to be(false)
      expect(config.complexity_of(create(:ticket))).to be_nil
    end

    it 'still saves blocks that do not touch the attribute' do
      group = create(:group)

      expect(described_class.update!(dispatch_group_id: group.id).dispatch_group_id).to eq(group.id)
    end
  end

  context 'with the complexity attribute', db_strategy: :reset do
    include_context 'with ticket distribution complexity'

    it 'is present' do
      expect(config.complexity_attribute_present?).to be(true)
    end

    it 'reads the assigned, not yet saved, value' do
      ticket = build(:ticket)
      ticket.complexidades = 'complexo'

      expect(config.complexity_of(ticket)).to eq('complexo')
    end

    it 'returns nil for an empty value' do
      expect(config.complexity_of(build(:ticket))).to be_nil
    end

    describe '.complexity_attribute_options' do
      subject(:options) { described_class.complexity_attribute_options }

      it 'includes the attribute with its options' do
        expect(options).to include(a_hash_including(name: 'complexidades', options: include('facil', 'moderado', 'complexo')))
      end

      it 'excludes system attributes' do
        expect(options.pluck(:name)).not_to include('state_id', 'priority_id', 'type', 'title')
      end
    end

    describe '.update!' do
      it 'rejects an attribute that is not a select' do
        expect { described_class.update!(complexity_attribute: 'title') }.to raise_error(Exceptions::UnprocessableEntity)
      end

      it 'accepts a select attribute' do
        expect(described_class.update!(complexity_attribute: 'complexidades').complexity_attribute).to eq('complexidades')
      end

      it 'rejects a negative weight' do
        expect { described_class.update!(weights: { 'facil' => -1 }) }.to raise_error(Exceptions::UnprocessableEntity)
      end

      it 'rejects a non-integer weight' do
        expect { described_class.update!(weights: { 'facil' => 'x' }) }.to raise_error(Exceptions::UnprocessableEntity)
      end

      it 'rejects ids that do not exist' do
        expect { described_class.update!(ignored_state_ids: [0]) }.to raise_error(Exceptions::UnprocessableEntity)
        expect { described_class.update!(ignored_priority_ids: [0]) }.to raise_error(Exceptions::UnprocessableEntity)
        expect { described_class.update!(dispatch_group_id: 0) }.to raise_error(Exceptions::UnprocessableEntity)
        expect { described_class.update!(dispatch_user_id: 0) }.to raise_error(Exceptions::UnprocessableEntity)
      end

      it 'keeps the other keys on a partial update' do
        group = create(:group)
        described_class.update!(dispatch_group_id: group.id)

        expect(described_class.current).to have_attributes(
          dispatch_group_id: group.id,
          weights:           { 'facil' => 1, 'moderado' => 3, 'complexo' => 6 },
        )
      end

      it 'coerces digit strings to integers and clears blank dispatch values' do
        group = create(:group)
        state = Ticket::State.first
        described_class.update!(dispatch_group_id: group.id.to_s, ignored_state_ids: [state.id.to_s, ''], weights: { 'facil' => '3' })

        expect(described_class.current).to have_attributes(dispatch_group_id: group.id, ignored_state_ids: [state.id], weights: { 'facil' => 3 })

        described_class.update!(dispatch_group_id: '')

        expect(described_class.current.dispatch_group_id).to be_nil
      end

      it 'rejects non-numeric values and non-array id lists' do
        expect { described_class.update!(dispatch_user_id: 'abc') }.to raise_error(Exceptions::UnprocessableEntity)
        expect { described_class.update!(ignored_state_ids: 'abc') }.to raise_error(Exceptions::UnprocessableEntity)
        expect { described_class.update!(weights: { 'facil' => 'abc' }) }.to raise_error(Exceptions::UnprocessableEntity)
      end

      it 'replaces the whole weights hash' do
        described_class.update!(weights: { 'facil' => 2 })

        expect(described_class.current.weights).to eq({ 'facil' => 2 })
      end
    end
  end
end
