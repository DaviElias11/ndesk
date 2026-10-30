# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

FactoryBot.define do
  factory :'ticket/distribution_member', aliases: %i[ticket_distribution_member] do
    user             { association :agent }
    level            { 'n2' }
    active           { true }
    last_assigned_at { nil }
    created_by_id    { 1 }
    updated_by_id    { 1 }

    trait :n1 do
      level { 'n1' }
    end
  end
end
