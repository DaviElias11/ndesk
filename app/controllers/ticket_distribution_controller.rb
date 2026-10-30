# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class TicketDistributionController < ApplicationController
  prepend_before_action :authenticate_and_authorize!

  # GET /api/v1/ticket_distribution
  def show
    render_overview
  end

  # PUT /api/v1/ticket_distribution
  def update
    Ticket::Distribution::Config.update!(config_params)
    render_overview
  end

  # POST /api/v1/ticket_distribution/members
  def member_create
    Ticket::DistributionMember.create!(params.permit(:user_id, :level))
    render_overview
  end

  # PUT /api/v1/ticket_distribution/members/:id
  def member_update
    member = Ticket::DistributionMember.find(params[:id])
    raise Exceptions::UnprocessableEntity, __('N1 agents have no switch.') if member.level == 'n1'

    member.update!(active: ActiveModel::Type::Boolean.new.cast(params[:active]))
    render_overview
  end

  # DELETE /api/v1/ticket_distribution/members/:id
  def member_destroy
    member = Ticket::DistributionMember.find(params[:id])

    if member.level == 'n1' && Ticket::DistributionMember.n1.where.not(id: member.id).none?
      raise Exceptions::UnprocessableEntity, __('The last N1 agent cannot be removed.')
    end

    member.destroy!
    render_overview
  end

  private

  def render_overview
    render json: Ticket::Distribution::Overview.new.as_json, status: :ok
  end

  def config_params
    params.permit(:complexity_attribute, :dispatch_group_id, :dispatch_user_id,
                  weights: {}, ignored_state_ids: [], ignored_priority_ids: []).to_h
  end
end
