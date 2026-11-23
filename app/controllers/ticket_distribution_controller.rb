# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class TicketDistributionController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  # GET /api/v1/ticket_distribution
  def show
    render_overview
  end

  # PUT /api/v1/ticket_distribution
  # Shows the configuration just saved: Config.current may still hold the values of this process (Setting.get cache).
  def update
    render_overview(config: Ticket::Distribution::Config.update!(config_params))
  end

  # POST /api/v1/ticket_distribution/members
  def member_create
    Ticket::Distribution::Roster.add!(user_id: params[:user_id], level: params[:level])
    render_overview
  end

  # PUT /api/v1/ticket_distribution/members/:id
  def member_update
    Ticket::Distribution::Roster.switch!(params[:id], active: switch_param)
    render_overview
  end

  # DELETE /api/v1/ticket_distribution/members/:id
  def member_destroy
    Ticket::Distribution::Roster.remove!(params[:id])
    render_overview
  end

  private

  def render_overview(config: Ticket::Distribution::Config.current)
    render json: Ticket::Distribution::Overview.new(config:).as_json, status: :ok
  end

  # Only a real boolean (or its text): any other value would turn the member on.
  def switch_param
    case params[:active]
    when true, 'true' then true
    when false, 'false' then false
    else raise Exceptions::UnprocessableEntity, __('The switch only accepts true or false.')
    end
  end

  # Unknown keys are ignored, but a known key that does not fit its format is refused instead of silently dropped.
  def config_params
    permitted = params.permit(:complexity_attribute, :dispatch_group_id, :dispatch_user_id,
                              weights: {}, ignored_state_ids: [], ignored_priority_ids: []).to_h
    given     = Ticket::Distribution::Config::DEFAULTS.keys & params.keys

    if given.empty? || (given - permitted.keys).any?
      raise Exceptions::UnprocessableEntity, __('The ticket distribution configuration has an invalid format.')
    end

    permitted
  end
end
