const commands = require(process.env.HOME + "/.atom/packages/julia-client/lib/package/commands")
const {runtime,misc,connection} = require(process.env.HOME + "/.atom/packages/julia-client")
const DOM = require(process.env.HOME + "/.kip/repos/jkroso/DOM.jl/runtime.js")

atom.commands.add(".item-views > atom-text-editor", {
  "julia-client:eval-block": (event) => {
    atom.commands.dispatch(event.currentTarget, "autocomplete-plus:cancel")
    commands.withInk(() => {
      connection.boot()
      eval_block()
    })
  },
  "julia-client:reset-module": () => {
    connection.boot()
    const {edpath} = runtime.evaluation.currentContext()
    connection.client.ipc.msg("reset module", edpath)
  },
  "julia-client:focus-result": () => {
    const {editor} = runtime.evaluation.currentContext()
    const cursors = misc.blocks.get(editor)
    if (cursors.length > 1) throw Error("Can't focus multiple results")
    const {range} = cursors[0]
    const [[start], [end]] = range
    const results = runtime.evaluation.ink.Result.forLines(editor, start, end)
    if (results.length > 1) throw Error("That selection has multiple results associated with it")
    if (results.length == 0) return
    const r = results[0]
    if (r.focused_node != null)
      r.focused_node.focus()
    else if (r.prev_focus != null)
      r.prev_focus.focus()
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

const keyboard_event = (e, top_node) => ({
  type: e.type,
  path: dom_path(e.target, top_node),
  key: e.key,
  modifiers: modifiers(e)
})

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

// The timeout used in DOM is too fast for Atom so we overwrite it
DOM.attrSetters.isfocused = (el, value) => value && setTimeout(() => el.focus(), 30)

const event_converters = {
  keydown: keyboard_event,
  keyup: keyboard_event,
  keypress: keyboard_event,
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
  const {editor, mod, edpath} = runtime.evaluation.currentContext()
  Promise.all(misc.blocks.get(editor).map(({range, line, text}) => {
    const [[start], [end]] = range
    const r = new runtime.evaluation.ink.Result(editor, [start, end], {type: "inline", scope: "julia"})
    const top_node = result_container()
    r.view.view.replaceWith(top_node)
    r.view.view = top_node
    runtime.evaluation.ink.highlight(editor, start, end)
    const _id = id += 1
    results[id] = r
    const onDidDestroy = () => {
      if (!(_id in results)) return
      delete results[_id]
      connection.client.ipc.msg("result done", _id)
    }
    r.onDidDestroy(onDidDestroy)
    editor.onDidDestroy(onDidDestroy)
    connection.client.ipc.msg("rutherford eval", {text, line: line+1, mod, path: edpath, id})
  }))
}

// creating it ourselves because ink attaches event handlers to their one
const result_container = () => {
  let el = document.createElement("div")
  el.setAttribute("tabindex", "-1")
  el.classList.add("ink", "result", "inline", "julia", "ink-hide", "loading")
  setTimeout(() => el.classList.remove("ink-hide"), 20)
  el.appendChild(loading_gear)
  return el
}

const loading_gear = document.createElement("span")
loading_gear.classList.add("loading", "icon", "icon-gear")

connection.client.ipc.handle("render", ({state, dom, id}) => {
  const r = results[id]
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

  r.focused_node = null
  r.prev_focus = null
  top_node.addEventListener("focusout", (e) => {
    top_node.style.boxShadow = ""
    r.prev_focus = null
    r.focused_node = e.target
  }, true)
  top_node.addEventListener("focusin", (e) => {
    top_node.style.boxShadow = "0px 0px 1px #1f96ff"
    r.prev_focus = e.relatedTarget
    r.focused_node = null
  }, true)
  top_node.addEventListener("mousedown", (e) => {
    if (r.focused_node != null) r.focused_node.focus()
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
  top_node.replaceChild(DOM.create(dom), loading_gear)

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
