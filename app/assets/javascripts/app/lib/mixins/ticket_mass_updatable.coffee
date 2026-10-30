InstanceMethods =
  ajax_mass_update: (data, success) ->
    @ajax_mass('update', data, success)

  ajax_mass_macro: (data, success) ->
    @ajax_mass('macro', data, success)

  ajax_mass: (path, data, success) ->
    @startLoading()

    @ajax(
      id: 'bulk_update'
      type: 'POST'
      url:   "#{@apiPath}/tickets/mass_#{path}"
      data: JSON.stringify(data)
      success: (data) =>
        @stopLoading()
        App.Collection.loadAssets(data.assets)
        App.Event.trigger('overview:fetch')
        App.Event.trigger('notify', {
          type: 'success'
          msg: __('Bulk action executed!')
        })

        success?()

      error: (xhr, status, error) =>
        @stopLoading()

        return if xhr.status != 422

        ticket = App.Ticket.find(xhr.responseJSON.ticket_id) if xhr.responseJSON.error

        if xhr.responseJSON?.unprocessable_entity is 'ticket_distribution.complexity_missing'
          titles = for id in xhr.responseJSON.ticket_ids || []
            App.Utils.htmlEscape(App.Ticket.find(id)?.title || "##{id}")
          message = [App.i18n.translateContent(xhr.responseJSON.error_human)].concat(titles).join('<br>')
        else if ticket
          message = App.i18n.translateContent(__('Ticket failed to save: %s'), ticket.title)
        else
          message = error

        new App.ErrorModal(
          head: __('Bulk action failed')
          contentInline: message
          container: @el.closest('.content')
        )
    )

App.TicketMassUpdatable =
  extended: ->
    @include InstanceMethods
