# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

Zammad::Application.routes.draw do
  api_path = Rails.configuration.api_path

  match "#{api_path}/ticket_distribution",             to: 'ticket_distribution#show',           via: :get
  match "#{api_path}/ticket_distribution",             to: 'ticket_distribution#update',         via: :put
  match "#{api_path}/ticket_distribution/members",     to: 'ticket_distribution#member_create',  via: :post
  match "#{api_path}/ticket_distribution/members/:id", to: 'ticket_distribution#member_update',  via: :put
  match "#{api_path}/ticket_distribution/members/:id", to: 'ticket_distribution#member_destroy', via: :delete
end
