# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

# Reads and writes the ticket distribution configuration, stored in the +ticket_distribution+ setting.
class Ticket::Distribution::Config
  SETTING = 'ticket_distribution'.freeze

  DEFAULTS = {
    'complexity_attribute' => 'complexidades',
    'weights'              => { 'facil' => 1, 'moderado' => 3, 'complexo' => 6 },
    'ignored_state_ids'    => [],
    'ignored_priority_ids' => [],
    'dispatch_group_id'    => nil,
    'dispatch_user_id'     => nil,
  }.freeze

  def self.current
    new(Setting.get(SETTING))
  end

  # Validates only the given keys and merges them (shallow, by top-level key) into the stored configuration.
  def self.update!(params)
    params = params.to_h.stringify_keys.slice(*DEFAULTS.keys)

    validate_complexity_attribute!(params['complexity_attribute']) if params.key?('complexity_attribute')
    validate_weights!(params['weights'])                           if params.key?('weights')
    validate_ids!(Ticket::State, params['ignored_state_ids']) if params.key?('ignored_state_ids')
    validate_ids!(Ticket::Priority, params['ignored_priority_ids']) if params.key?('ignored_priority_ids')
    validate_ids!(::Group, params['dispatch_group_id'])              if params.key?('dispatch_group_id')
    validate_ids!(::User, params['dispatch_user_id'])                if params.key?('dispatch_user_id')

    Setting.set(SETTING, current.to_h.merge(params))
    current
  end

  # Ticket attributes that can be used as the complexity source: active, editable selects without relation.
  def self.complexity_attribute_options
    ObjectManager::Attribute
      .where(object_lookup_id: ObjectLookup.by_name('Ticket'), active: true, editable: true, data_type: 'select')
      .reject { |attribute| attribute.data_option['relation'].present? }
      .map { |attribute| { name: attribute.name, display: attribute.display, options: option_hash(attribute) } }
  end

  def self.option_hash(attribute)
    options = attribute.data_option['options']

    return options.to_h { |option| [option['value'].to_s, option['name'].to_s] } if options.is_a?(Array)

    (options || {}).to_h { |key, display| [key.to_s, display.to_s] }
  end
  private_class_method :option_hash

  def self.validate_complexity_attribute!(name)
    return if complexity_attribute_options.any? { |option| option[:name] == name }

    raise Exceptions::UnprocessableEntity, __('The complexity attribute must be an active select attribute of tickets.')
  end
  private_class_method :validate_complexity_attribute!

  def self.validate_weights!(weights)
    valid = weights.respond_to?(:all?) && weights.all? { |_, weight| weight.is_a?(Integer) && weight >= 0 }

    return if valid

    raise Exceptions::UnprocessableEntity, __('Each weight must be an integer greater than or equal to 0.')
  end
  private_class_method :validate_weights!

  def self.validate_ids!(model, ids)
    ids = Array(ids).compact

    return if model.where(id: ids).count == ids.uniq.size

    raise Exceptions::UnprocessableEntity, __('The selected record does not exist.')
  end
  private_class_method :validate_ids!

  def initialize(state)
    @values = DEFAULTS.deep_dup.merge((state || {}).to_h.with_indifferent_access.slice(*DEFAULTS.keys))
  end

  def to_h
    @values.deep_dup
  end

  DEFAULTS.each_key do |key|
    define_method(key) { @values[key] }
  end

  def weight_for(value)
    weights[value.to_s]
  end

  def complexity_attribute_present?
    Ticket.column_names.include?(complexity_attribute) &&
      ObjectManager::Attribute.get(object: 'Ticket', name: complexity_attribute)&.active == true
  end

  def complexity_of(ticket)
    return if !complexity_attribute_present?

    ticket[complexity_attribute].presence
  end
end
