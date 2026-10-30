# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

require 'rails_helper'

class SampleModel
  include ActiveModel::Validations

  attr_accessor :sample

  validates :sample, 'validations/verify_perform_rules': true
end

RSpec.describe Validations::VerifyPerformRulesValidator do
  let(:instance) { SampleModel.new }

  context 'when validating presence' do
    it 'is valid when attribute is empty' do
      instance.sample = {}
      expect(instance).to be_valid
    end

    it 'is valid when attribute is nil' do
      instance.sample = nil
      expect(instance).to be_valid
    end

    it 'is valid when attribute does not have checkable keys' do
      instance.sample = { test: :value }
      expect(instance).to be_valid
    end

    it 'is valid when required value is present' do
      instance.sample = { 'article.note' => { 'body' => 'a', 'subject' => 'b', 'internal' => 'c' } }
      expect(instance).to be_valid
    end

    it 'is invalid when required value is missing' do
      instance.sample = { 'article.note' => {} }
      instance.valid?

      expect(instance.errors).to have_attributes(
        errors: include(have_attributes(message: match(%r{The required 'sample' value for article.note, internal is missing!})))
      )
    end

    it 'is invalid when required value is partially missing' do
      instance.sample = { 'article.note' => { 'body' => 'a', 'subject' => 'b' } }
      instance.valid?

      expect(instance.errors).to have_attributes(
        errors: include(have_attributes(message: match(%r{The required 'sample' value for article.note, internal is missing!})))
      )
    end
  end

  context 'when validating the ticket distribution action', :aggregate_failures do
    it 'makes a macro without mode invalid' do
      macro = build(:macro, perform: { 'distribution.ticket_distribution' => {} })

      expect(macro).not_to be_valid
      expect(macro.errors.full_messages.join).to include('distribution.ticket_distribution, value')
    end

    it 'makes a macro with an unknown mode invalid' do
      macro = build(:macro, perform: { 'distribution.ticket_distribution' => { 'value' => 'foo' } })

      expect(macro).not_to be_valid
      expect(macro.errors.full_messages.join).to include('distribution.ticket_distribution, value')
    end

    %w[entry handover reopening].each do |mode|
      it "accepts the mode #{mode}" do
        expect(build(:macro, perform: { 'distribution.ticket_distribution' => { 'value' => mode } })).to be_valid
      end
    end
  end

  context 'when validating presence with precondition' do
    it 'is valid when required value for specific precondition is present' do
      instance.sample = { 'ticket.customer_id' => { 'pre_condition' => 'specific', 'value' => '123' } }
      expect(instance).to be_valid
    end

    it 'is valid when required value without specific precondition is not present' do
      instance.sample = { 'ticket.customer_id' => { 'pre_condition' => 'current' } }
      expect(instance).to be_valid
    end

    it 'is invalid when required value for specific precondition is not present' do
      instance.sample = { 'ticket.customer_id' => { 'pre_condition' => 'specific', 'value' => '' } }
      instance.valid?

      expect(instance.errors).to have_attributes(
        errors: include(have_attributes(message: match(%r{The required 'sample' value for ticket.customer_id, value is missing!})))
      )
    end
  end
end
