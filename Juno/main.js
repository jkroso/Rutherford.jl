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

const dom_path = (dom, top_node) => {
  const indices = []
  if (!top_node.contains(dom)) return indices
  while (dom != top_node) {
    indices.push(indexOf(dom))
    dom = dom.parentNode
  }
  return indices.reverse()
}

const indexOf = (dom) => {
  var i = 0
  var children = dom.parentNode.childNodes
  while (children[i++] != dom);
  return i
}

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
    runtime.evaluation.ink.highlight(editor, start, end)
    const _id = id += 1
    results[id] = r
    const onDidDestroy = () => {
      if (!(_id in results)) return
      connection.client.ipc.msg("result done", _id)
      delete results[_id]
    }
    r.onDidDestroy(onDidDestroy)
    editor.onDidDestroy(onDidDestroy)
    connection.client.ipc.msg("rutherford eval", {text, line: line+1, mod, path: edpath, id})
  }))
}

var dock_item = null
var node_to_focus = null
const right_dock = atom.workspace.getRightDock()
const right_pane = right_dock.getActivePane()

connection.client.ipc.handle("render", ({state, dom, id, location}) => {
  const r = results[id]
  if (location == "dock") {
    // hide the inline result that was showing the loading icon
    delete results[id]
    r.destroy()
    var item = DOM.create(dom)
    if (dock_item == null) {
      dock_item = right_pane.addItem({
        element: item,
        getTitle() { return "UI"},
        id
      })
      var top_node = item.parentNode
      top_node.addEventListener("focusout", (e) => {
        if (!right_pane.focused) node_to_focus = e.target
      }, true)
      top_node.addEventListener("mousedown", () => {
        if (!right_pane.focused)  {
          right_pane.activate()
          node_to_focus && node_to_focus.focus()
        }
      }, true)
    } else {
      var tmp = dock_item.element.parentNode
      var top_node = tmp.cloneNode()
      tmp.replaceWith(top_node)
      top_node.appendChild(item)
      dock_item.element = item
    }
    results[id] = dock_item
  } else {
    r.view.view.innerHTML = ""
    r.view.view.classList.toggle("error", state == "error")
    r.view.view.classList.remove("loading")
    r.view.view.appendChild(DOM.create(dom))
    r.view.toolbarView.classList.remove("hide")
    var top_node = r.view.view
  }
  const sendEvent = (e) => {
    connection.client.ipc.msg("event", id, eventJSON(e, top_node.lastChild))
    e.stopPropagation()
    e.preventDefault()
  }
  for (name in event_converters) {
    top_node.addEventListener(name, sendEvent, true)
  }
  runtime.workspace.update()
})

const top_node = (x) => x === dock_item ? x.element : x.view.view.lastChild

connection.client.ipc.handle("patch", ({id, patch}) => {
  DOM.patch(patch, top_node(results[id]))
})

connection.client.ipc.handle("open", ({file, line}) => {
  runtime.workspace.ink.Opener.open(file, line)
})

connection.client.ipc.handle("AsyncNode", ({id, value}) => {
  document.getElementById(String(id)).replaceWith(DOM.create(value))
})
