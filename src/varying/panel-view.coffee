{ Varying, Model, attribute, bind, DomView, template, find, from } = require('janus')
$ = require('janus-dollar')
{ DateTime } = require('luxon')

{ WrappedVarying, Reaction } = require('./inspector')


################################################################################
# REACTION VIEW (list)

ReactionVM = Model.build(
  bind('at', from('subject').watch('at').map(DateTime.fromJSDate))
  bind('change_count', from('subject').watch('changes').flatMap((cs) -> cs.watchLength()))
  bind('target', from('settings.target').and('subject').all.flatMap((target, subject) ->
    if target?
      subject.watchNode(target)
    else
      subject.watch('changes').flatMap((cs) -> cs.watchAt(-1))
  ))
  bind('root', from('target').and('subject').watch('root').all.map((t, r) -> r unless t is r))
)

ReactionView = DomView.withOptions({ viewModelClass: ReactionVM }).build($('
    <div class="reaction">
      <div class="time"><span class="minor"/><span class="major"/></div>

      <div class="reaction-part reaction-inspectionTarget">
        <div class="reaction-part-id"/>
        <div class="reaction-part-delta"/>
      </div>
      <div class="reaction-intermediate">
        <span class="ellipsis">&vellip;</span>
        <span class="multiple">&times;<span class="count"/></span>
      </div>
      <div class="reaction-part reaction-root">
        <div class="reaction-part-id"/>
        <div class="reaction-part-delta"/>
      </div>
    </div>
  '), template(

    find('.time .minor').text(from('at').map((t) -> t.toFormat("HH:mm:")))
    find('.time .major').text(from('at').map((t) -> t.toFormat("ss.SSS")))

    find('.reaction-inspectionTarget .reaction-part-id').text(from('target').watch('id').map((id) -> "##{id}"))
    find('.reaction-inspectionTarget .reaction-part-delta').render(from('target')).context('delta')

    find('.reaction-intermediate').classed('hide', from('change_count').map((x) -> x < 3))
    find('.reaction-intermediate .count').text(from('change_count').map((cc) -> cc - 2))

    find('.reaction-root').classed('hide', from('root').map((r) -> !r?))
    find('.reaction-root .reaction-part-id').text(from('root').watch('id').map((id) -> "##{id}"))
    find('.reaction-root .reaction-part-delta').render(from('root')).context('delta')
  )
)


################################################################################
# VARYING DELTA -> VIEW

VaryingDeltaView = DomView.build($('
    <div class="varyingDelta">
      <div class="value"/>
      <div class="delta">
        <div class="separator"/>
        <div class="newValue"/>
      </div>
    </div>
  '), template(

    find('.value').render(from('immediate').and('value').all.map((i, v) -> v ? i)).context('debug')
    find('.newValue').render(from('new_value')).context(from('changed').map((changed) -> 'debug' if changed is true))

    find('.varyingDelta').classed('hasDelta', from('changed'))
  )
)


################################################################################
# VARYING TREE VIEW

VaryingTreeView = DomView.build($('
    <div class="varying-tree">
      <div class="main">
        <div class="node">
          <div class="inner-marker"/>
          <div class="value-marker"/>
        </div>
        <div class="text">
          <p class="title">
            <span class="className"/>
            <span class="uid"/>
          </p>
          <div class="valueSection">
            <ul class="tags">
              <li class="tagOutdated">Outdated</li>
              <li class="tagImmediate">Immediate</li>
            </ul>
            <div class="valueContainer"/>
          </div>
        </div>
      </div>
      <div class="aux">
        <div class="varying-tree-inner varying-tree-innerNew"/>
        <div class="varying-tree-inner varying-tree-innerMain"/>
        <div class="mapping"><span>λ</span></div>
      </div>
      <div class="varying-tree-next"/>
      <div class="varying-tree-nexts"/>
    </div>
  '), template(

    find('.varying-tree')
      .classed('derived', from('derived'))
      .classed('flattened', from('flattened'))
      .classed('mapped', from('mapped'))

      .classed('hasObservations', from('observations').flatMap((os) -> os.watchLength().map((l) -> l > 0)))
      .classed('hasValue', from('value').map((x) -> x?))
      .classed('hasInner', from('inner').map((x) -> x?))

    find('.tagOutdated').classed('hide', from('derived').and('immediate').and('value')
      .and('observations').flatMap((os) -> os.watchLength())
      .all.map((derived, immediate, value, osl) -> !derived or (osl > 0) or !(immediate? or value?)))
    find('.tagImmediate').classed('hide', from('immediate').map((x) -> !x?))

    find('.title .className').text(from('title'))
    find('.title .uid').text(from('id').map((x) -> "##{x}"))

    find('.valueContainer').render(from((x) -> x)).context('delta') # TODO: ehhh on this context name?

    #find('.mapping').flyout(from((x) -> x).and('mapped').all.map((wv, mapped) -> wv if mapped is true)).context('mapping')

    find('.varying-tree-innerNew')
      .classed('hasNewInner', from('new_inner').map((x) -> x?))
      .render(from('new_inner').map((v) -> WrappedVarying.hijack(v) if v?)).context('tree')
    find('.varying-tree-innerMain').render(from('inner').map((v) -> WrappedVarying.hijack(v) if v?)).context('tree')
    find('.varying-tree-next').render(from('parent').map((v) -> WrappedVarying.hijack(v) if v?)).context('tree')
    find('.varying-tree-nexts').render(from('parents').map((x) -> x?.map((v) -> WrappedVarying.hijack(v))))
      .context('linked').options( itemContext: 'tree' )
  )
)


################################################################################
# VARYING PANEL

class VaryingPanel extends Model.build(
  attribute('active_reaction', class extends attribute.Enum
    nullable: true
    values: -> this.model.watch('subject').flatMap((wv) -> wv.watch('reactions'))
    default: -> null
  )
)

VaryingView = DomView.withOptions({ viewModelClass: VaryingPanel }).build($('
    <div class="janus-inspect-panel janus-inspect-varying">
      <div class="panel-title">
        Varying #<span class="varying-id"/>
        <span class="varying-snapshot">
          Snapshot
          <a class="varying-snapshot-close" href="#close">Close</a>
        </span>
      </div>
      <div class="panel-sidebar">
        <div class="panel-sidebar-title">Reactions</div>
        <div class="panel-sidebar-content varying-reactions"/>
      </div>
      <div class="panel-content">
        <div class="varying-inert">
          Inert (no observers).
          <a class="varying-observe" href="#react">Observe now</a>.
        </div>
        <div class="varying-tree"/>
      </div>
    </div>
  '), template(
    find('.varying-id').text(from('subject').watch('id'))

    find('.varying-snapshot').classed('hide', from('active_reaction').map((x) -> !x?))
    find('.varying-snapshot-close').on('click', (event, subject) ->
      event.preventDefault()
      subject.unset('active_reaction')
    )

    find('.varying-inert').classed('hide', from('subject').watch('observations')
      .flatMap((obs) -> obs?.watchNonEmpty()))

    find('.varying-observe').on('click', (event, wv) ->
      event.preventDefault()
      wv.get('subject').varying.react()
    )

    find('.varying-tree').render(from('subject').and('active_reaction').all.flatMap((wv, ar) ->
      if ar? then wv.watch('id').flatMap((id) -> ar.watch("tree.#{id}")) else wv
    )).context('tree')

    find('.varying-reactions').render(from.attribute('active_reaction'))
      .context('edit').criteria( style: 'list' )
      .options(from('subject').map((wv) -> { renderItem: (x) -> x.options( settings: { target: wv } ) }))
  )
)

module.exports = {
  VaryingDeltaView
  VaryingTreeView
  VaryingView
  ReactionView

  registerWith: (library) ->
    library.register(WrappedVarying, VaryingDeltaView, context: 'delta')
    library.register(WrappedVarying, VaryingTreeView, context: 'tree')
    library.register(WrappedVarying, VaryingView, context: 'panel')
    library.register(Reaction, ReactionView)
}
