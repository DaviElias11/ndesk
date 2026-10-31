class App.TicketDistribution extends App.ControllerSubContent
  @requiredPermission: 'admin.ticket_distribution'
  header: __('Ticket Distribution')

  events:
    'change .js-addMember':           'addMember'
    'change .js-memberActive':        'switchMember'
    'click .js-removeMember':         'removeMember'
    'submit .js-dispatch':            'saveDispatch'
    'submit .js-load':                'saveLoad'
    'change .js-complexityAttribute': 'renderWeights'

  constructor: ->
    super
    @startLoading()
    @fetch()

  # The controller stays alive while the admin works elsewhere: coming back shows the load of now.
  show: =>
    super
    @fetch() if @overview

  fetch: =>
    @ajax(
      type:    'GET'
      url:     @url()
      success: @render
      error:   @notifyError
    )

  render: (@overview) =>
    @stopLoading()

    @html App.view('ticket_distribution/index')(
      overview:        @overview
      n1Options:       @agentsOutOf(@overview.n1)
      n2Options:       @agentsOutOf(@overview.n2)
      maxPoints:       Math.max(1, _.max(_.pluck(@overview.n2, 'points')))
      previewMember:   _.findWhere(@overview.n2, user_id: @overview.preview_user_id)
      situationLabel:  @situationLabel
      problemMessages: @problemMessages
    )

    @renderIgnored('.js-ignoredStates', 'ignored_state_ids', @overview.options.states, @overview.config.ignored_state_ids)
    @renderIgnored('.js-ignoredPriorities', 'ignored_priority_ids', @overview.options.priorities, @overview.config.ignored_priority_ids)
    @renderWeights()

  renderIgnored: (selector, name, records, value) =>
    @$(selector).html(App.UiElement.column_select.render(
      name:      name
      options:   ({ value: record.id.toString(), name: record.name } for record in records)
      value:     (id.toString() for id in value)
      translate: true
    ))

  # The weights follow the attribute picked in the form, even before it is saved. A value without weight shows 0.
  renderWeights: =>
    attribute = _.findWhere(@overview.options.complexity_attributes, name: @$('.js-complexityAttribute').val())
    options   = attribute?.options || {}

    @$('.js-weights').html App.view('ticket_distribution/weights')(
      weights: ({ value: value, name: name, points: @overview.config.weights[value] ? 0 } for value, name of options)
    )

  addMember: (e) =>
    select = $(e.currentTarget)
    return if !select.val()

    @saveMember('POST', '/members', { user_id: select.val(), level: select.attr('data-level') })

  switchMember: (e) =>
    input = $(e.currentTarget)

    @saveMember('PUT', "/members/#{input.attr('data-member-id')}", { active: input.prop('checked') })

  removeMember: (e) =>
    e.preventDefault()

    @saveMember('DELETE', "/members/#{$(e.currentTarget).attr('data-member-id')}")

  saveDispatch: (e) =>
    e.preventDefault()

    @saveConfig(
      dispatch_group_id: @$('.js-dispatch select[name="dispatch_group_id"]').val()
      dispatch_user_id:  @$('.js-dispatch select[name="dispatch_user_id"]').val()
    )

  saveLoad: (e) =>
    e.preventDefault()

    params =
      ignored_state_ids:    @$('.js-ignoredStates select').val() || []
      ignored_priority_ids: @$('.js-ignoredPriorities select').val() || []

    # Without a selectable attribute (the configured one is gone) the stored attribute and weights stay as they are.
    attribute = @$('.js-complexityAttribute').val()
    if attribute
      params.complexity_attribute = attribute
      params.weights = {}
      @$('.js-weight').each((index, input) ->
        params.weights[$(input).attr('data-value')] = $(input).val()
      )

    @saveConfig(params)

  # The switch and the add field already show the change, so a refused one needs the state of the server back.
  saveMember: (type, path, params) =>
    @write(type, path, params, @render, (xhr) =>
      @notifyError(xhr)
      @fetch()
    )

  # A refused save keeps the form as it is, with what was typed.
  saveConfig: (params) =>
    success = (overview) =>
      @render(overview)
      @notify(type: 'success', msg: __('Update successful.'))

    @write('PUT', '', params, success, @notifyError)

  # Queued, so the last response to arrive is the one of the last change.
  write: (type, path, params, success, error) =>
    @ajax(
      type:    type
      url:     @url(path)
      data:    JSON.stringify(params)
      queue:   true
      success: success
      error:   error
    )

  url: (path = '') =>
    "#{@apiPath}/ticket_distribution#{path}"

  notifyError: (xhr) =>
    details = xhr.responseJSON || {}

    @notify(
      type: 'error'
      msg:  details.error_human || details.error || __('The ticket distribution could not be updated.')
    )

  agentsOutOf: (members) =>
    memberIds = _.pluck(members, 'user_id')

    _.reject(@overview.options.agents, (agent) -> _.contains(memberIds, agent.id))

  situationLabel: (member) ->
    switch member.situation
      when 'off' then App.i18n.translatePlain(__('Switched off'))
      when 'out_of_office' then App.i18n.translatePlain(__('Out of office until %s'), App.i18n.translateDate(member.out_of_office_end_at))
      when 'offline' then App.i18n.translatePlain(__('Offline · still in rotation'))
      else App.i18n.translatePlain(__('In rotation'))

  problemMessages: (problems) ->
    for problem in problems
      switch problem.type
        when 'inactive' then App.i18n.translatePlain(__('Inactive user'))
        when 'not_agent' then App.i18n.translatePlain(__('Not an agent (no ticket.agent permission)'))
        else App.i18n.translatePlain(__('No access to: %s'), problem.groups.join(', '))

App.Config.set('TicketDistribution', { prio: 2315, name: __('Ticket Distribution'), parent: '#manage', target: '#manage/ticket_distribution', controller: App.TicketDistribution, permission: ['admin.ticket_distribution'] }, 'NavBarAdmin')
