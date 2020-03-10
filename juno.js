const commands = require(process.env.HOME + "/.atom/packages/julia-client/lib/package/commands")
const {runtime,misc,connection} = require(process.env.HOME + "/.atom/packages/julia-client")
const Highlighter = require(process.env.HOME + "/.atom/packages/julia-client/lib/ui/highlighter.coffee")
const DOM = require(process.env.HOME + "/.kip/repos/jkroso/DOM.jl/runtime.js")

atom.commands.add(".item-views > atom-text-editor", {
  "julia-client:eval-block": (event) => {
    atom.commands.dispatch(event.currentTarget, "autocomplete-plus:cancel")
    return commands.withInk(() => {
      connection.boot()
      return eval_block()
    })
  },
  "julia-client:eval-each": (event) => {
    atom.commands.dispatch(event.currentTarget, "autocomplete-plus:cancel")
    return commands.withInk(() => {
      connection.boot()
      return eval_each()
    })
  },
  "julia-client:reset-module": () => {
    connection.boot()
    const {edpath} = runtime.evaluation._currentContext()
    connection.client.ipc.msg("reset module", edpath)
  },
  "julia-client:focus-result": () => {
    const {editor} = runtime.evaluation._currentContext()
    const cursors = misc.blocks.get(editor)
    if (cursors.length > 1) throw Error("Can't focus multiple results")
    const {range} = cursors[0]
    const [[start], [end]] = range
    const results = runtime.evaluation.ink.Result.forLines(editor, start, end)
    if (results.length > 1) throw Error("That selection has multiple results associated with it")
    if (results.length == 0) return
    const r = results[0]
    r.isfocused || r.focus_trap.focus()
  }
})

var style = document.createElement("style")
document.head.appendChild(style)

connection.client.ipc.handle("stylechange", (data) => {
  const node = DOM.create(data)
  style.replaceWith(node)
  style = node
})

const eventJSON = (e, top_node) => event_converters[e.type](e, top_node)

const modifiers = (e) => {
  const mods = []
  if (e.altKey) mods.push("alt")
  if (e.ctrlKey) mods.push("ctrl")
  if (e.shiftKey) mods.push("shift")
  if (e.metaKey) mods.push("meta")
  return mods
}

const mouse_button_event = (e, top_node) => ({
  type: e.type,
  path: dom_path(e.target, top_node),
  button: e.button,
  position: [e.x, e.y]
})

const mouse_hover_event = (e, top_node) => ({
  type: e.type,
  path: dom_path(e.target, top_node)
})

const dom_path = (dom, top_node) => top_node.contains(dom) ? DOM.dom_path(dom, top_node) : []

const event_converters = {
  click: mouse_button_event,
  dblclick: mouse_button_event,
  mousedown: mouse_button_event,
  mouseup: mouse_button_event,
  mouseover: mouse_hover_event,
  mouseout: mouse_hover_event,
  resize() {
    return {
      type: "resize",
      width: window.innerWidth,
      height: window.innerHeight,
    }
  },
  scroll(e, top_node) {
    return {
      type: "scroll",
      path: dom_path(e.target, top_node),
      position: [window.scrollX, window.scrollY]
    }
  },
  mousemove(e, top_node) {
    return {
      type: "mousemove",
      path: dom_path(e.target, top_node),
      position: [e.x, e.y]
    }
  }
}

const results = {}
var id = 0

const eval_block = () => {
  const ctx = runtime.evaluation._currentContext()
  const results = misc.blocks.get(ctx.editor).map((x)=>create_result(x, ctx))
  return connection.client.ipc.rpc("rutherford eval", results)
}

const create_result = ({range, line, text}, {editor, mod, edpath}) => {
  const [[start], [end]] = range
  const r = new runtime.evaluation.ink.Result(editor, [start, end], {type: "inline", scope: "julia"})
  const top_node = result_container()
  r.view.view.replaceWith(top_node)
  r.view.view = top_node
  runtime.evaluation.ink.highlight(editor, start, end)
  const _id = id += 1
  results[_id] = r
  const onDidDestroy = () => {
    if (!(_id in results)) return
    delete results[_id]
    connection.client.ipc.msg("result done", _id)
  }
  r.onDidDestroy(onDidDestroy)
  editor.onDidDestroy(onDidDestroy)
  return {text, line: line+1, path: edpath, id: _id}
}

const eval_each = () => {
  const ctx = runtime.evaluation._currentContext()
  const src = ctx.editor.getBuffer().getText()
  const cursors = misc.blocks.get(ctx.editor)
  if (cursors.length == 0) cursors.push({range:[[0,0],[0,null]]})
  return Promise.all(cursors.map(({range}) =>
    connection.client.ipc.rpc("getblocks", range, ctx.edpath, src)
      .then((blocks) => blocks.map((x)=>create_result(x, ctx)))
      .then((results) => connection.client.ipc.rpc("rutherford eval", results))
  ))
}

// creating it ourselves because ink attaches event handlers to their one
const result_container = () => {
  let el = document.createElement("div")
  el.setAttribute("tabindex", "-1")
  el.classList.add("ink", "result", "inline", "julia", "ink-hide", "loading")
  setTimeout(() => el.classList.remove("ink-hide"), 20)
  el.appendChild(loading_gear.cloneNode())
  el.style.minHeight = "1.5em"
  el.style.maxHeight = window.innerHeight/2 + "px"
  return el
}

const loading_gear = document.createElement("span")
loading_gear.classList.add("loading", "icon", "icon-gear")

const notifications = {}

connection.client.ipc.handle("test passed", ({line}) => {
  if (line in notifications) {
    notifications[line].dismiss()
  }
})

connection.client.ipc.handle("test failed", ({line, path}) => {
  const n = atom.notifications.addInfo(`Test failed in ${path}:${line}`, {
    dismissable: true,
    buttons: [{
      onDidClick: () => {
        runtime.workspace.ink.Opener.open(path, line-1)
      },
      text: "Goto"
    }]
  })
  if (line in notifications) notifications[line].dismiss()
  n.onDidDismiss(()=>{delete notifications[line]})
  notifications[line] = n
})

connection.client.ipc.handle("render", ({state, dom, id}) => {
  const r = results[id]
  if (r == undefined) return
  r.view.toolbarView.classList.remove("hide")
  var top_node = r.view.view

  top_node.addEventListener("mousewheel", (e) => {
    var node = e.target
    while (node != top_node) {
      if ((node.offsetHeight != node.scrollHeight || node.offsetWidth != node.scrollWidth) &&
          ((e.deltaY > 0 && node.scrollHeight - node.scrollTop > node.clientHeight) ||
           (e.deltaY < 0 && node.scrollTop > 0) ||
           (e.deltaX > 0 && node.scrollWidth - node.scrollLeft > node.clientWidth) ||
           (e.deltaX < 0 && node.scrollLeft > 0))) {
        e.stopPropagation()
        break
      }
      node = node.parentNode
    }
  }, true)

  r.focus_trap = document.createElement('input')
  r.focus_trap.setAttribute("type", "text")
  r.focus_trap.style.position = "absolute"
  r.focus_trap.style.opacity = "0"
  r.focus_trap.style.zIndex = "-999"
  r.focus_trap.style.width = "0"
  r.focus_trap.style.height = "0"

  const sendKeyEvent = (e) => {
    connection.client.ipc.msg("event", id, {type: e.type, key: e.key, modifiers: modifiers(e)})
    e.preventDefault()
    e.stopPropagation()
  }

  r.focus_trap.addEventListener("keydown", sendKeyEvent, true)
  r.focus_trap.addEventListener("keyup", sendKeyEvent, true)
  r.focus_trap.addEventListener("keypress", (e) => {
    e.preventDefault()
    e.stopPropagation()
  }, true)

  r.prev_focus = null
  r.isfocused = false
  r.focus_trap.addEventListener("focusout", (e) => {
    top_node.style.boxShadow = ""
    r.isfocused = false
  }, true)
  r.focus_trap.addEventListener("focusin", (e) => {
    top_node.style.boxShadow = "0px 0px 1px #1f96ff"
    r.prev_focus = e.relatedTarget
    r.isfocused = true
  }, true)
  top_node.addEventListener("mousedown", (e) => {
    r.isfocused || r.focus_trap.focus()
  }, true)
  top_node.addEventListener("keydown", (e) => {
    if (e.key == "Escape") r.prev_focus.focus()
  }, true)

  const sendEvent = (e) => {
    connection.client.ipc.msg("event", id, eventJSON(e, top_node.lastChild))
    e.preventDefault()
    e.stopPropagation()
  }
  for (name in event_converters) {
    top_node.addEventListener(name, sendEvent, true)
  }

  top_node.classList.toggle("error", state == "error")
  top_node.classList.remove("loading")
  top_node.replaceChild(r.focus_trap, top_node.lastChild)
  top_node.appendChild(DOM.create(dom))

  runtime.workspace.update()
})

connection.client.ipc.handle("patch", ({id, patch, state}) => {
  const top_node = results[id].view.view
  top_node.classList.toggle("error", state == "error")
  DOM.patch(patch, top_node.lastChild)
})

connection.client.ipc.handle("open", ({file, line}) => {
  runtime.workspace.ink.Opener.open(file, line)
})

connection.client.ipc.handle("AsyncNode", ({id, value}) => {
  document.getElementById(String(id)).replaceWith(DOM.create(value))
})

connection.client.ipc.handle("edit", (src, line, id) => {
  const {editor} = runtime.evaluation._currentContext()
  const result = results[id]
  result.text = src // prevent invalidation
  const marker = result.marker
  const range = marker.getBufferRange()
  editor.setTextInBufferRange(range, src)
})

connection.client.ipc.handle("highlight", ({src, grammer, block}) => {
  grammar = atom.grammars.grammarForScopeName(grammer)
  return Highlighter.highlight(src, grammar, {scopePrefix: 'syntax--', block})
})
