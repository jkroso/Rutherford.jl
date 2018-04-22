commands = require process.env.HOME + "/.atom/packages/julia-client/lib/package/commands"
{runtime,misc,connection} = require process.env.HOME + "/.atom/packages/julia-client"
DOM = require process.env.HOME + "/.kip/repos/jkroso/DOM.jl/runtime.js"

atom.commands.add ".item-views > atom-text-editor",
  "julia-client:eval-block": (event) =>
    atom.commands.dispatch(event.currentTarget, "autocomplete-plus:cancel")
    commands.withInk ->
      connection.boot()
      eval_block()
  "julia-client:reset-module": (event) =>
    connection.boot()
    {edpath} = runtime.evaluation.currentContext()
    connection.client.ipc.msg("reset-module", edpath)

style = document.createElement("style")
document.head.appendChild(style)

connection.client.ipc.handle "stylechange", (data) ->
  node = DOM.create(data)
  style.replaceWith(node)
  style = node

eventJSON = (e, top_node) -> event_converters[e.type](e, top_node)

modifiers = (e) ->
  mods = []
  mods.push("alt") if e.altKey
  mods.push("ctrl") if e.ctrlKey
  mods.push("shift") if e.shiftKey
  mods.push("meta") if e.metaKey
  mods

keyboard_event = (e, top_node) ->
  type: e.type
  path: dom_path(e.target, top_node)
  key: e.key
  modifiers: modifiers(e)

mouse_button_event = (e, top_node) ->
  type: e.type
  path: dom_path(e.target, top_node)
  button: e.button
  position: [e.x, e.y]

mouse_hover_event = (e, top_node) ->
  type: e.type
  path: dom_path(e.target, top_node)

dom_path = (dom, top_node) ->
  indices = []
  return indices if not top_node.contains(dom)
  while dom != top_node
    indices.push(indexOf(dom))
    dom = dom.parentNode
  indices.reverse()

indexOf = (dom) ->
  i = 0
  children = dom.parentNode.childNodes
  while children[i++] != dom then
  i

event_converters =
  keydown: keyboard_event
  keyup: keyboard_event
  keypress: keyboard_event
  click: mouse_button_event
  dblclick: mouse_button_event
  mousedown: mouse_button_event
  mouseup: mouse_button_event
  mouseover: mouse_hover_event
  mouseout: mouse_hover_event
  resize: (e) ->
    type: "resize"
    width: window.innerWidth
    height: window.innerHeight
  scroll: (e, top_node) ->
    type: e.type
    path: dom_path(e.target, top_node)
    position: [window.scrollX, window.scrollY]
  mousemove: (e, top_node) ->
    type: e.type
    path: dom_path(e.target, top_node)
    position: [e.x, e.y]

results = {}
id = 0

eval_block = () ->
  {editor, mod, edpath} = runtime.evaluation.currentContext()
  Promise.all misc.blocks.get(editor).map ({range, line, text, selection}) =>
    [[start], [end]] = range
    runtime.evaluation.ink.highlight editor, start, end
    _id = id += 1
    results[id] = new runtime.evaluation.ink.Result editor, [start, end], {type: "inline", scope: "julia"}
    onDidDestroy = () =>
      return if _id not of results
      connection.client.ipc.msg("result-done", _id)
      delete results[_id]
    results[id].onDidDestroy onDidDestroy
    editor.onDidDestroy onDidDestroy
    connection.client.ipc.msg("RutherfordEval", {text, line: line+1, mod, path: edpath, id})

connection.client.ipc.handle "render", ({type, dom, id}) ->
  r = results[id]
  r.setContent DOM.create(dom), {error: type == "error"}
  sendEvent = (e) ->
    connection.client.ipc.msg("event", id, eventJSON(e, r.view.view.lastElementChild))
    e.stopPropagation()
    e.preventDefault()
  for name of event_converters
    r.view.view.addEventListener(name, sendEvent, true)
  runtime.workspace.update()

connection.client.ipc.handle "patch", ({id, patch}) ->
  r = results[id]
  DOM.patch(patch, r.view.view.lastChild)

connection.client.ipc.handle "open", ({file, line}) ->
  runtime.workspace.ink.Opener.open(file, line)

connection.client.ipc.handle "AsyncNode", ({id, value}) ->
  document.getElementById(String(id))
          .replaceWith(DOM.create(value))
