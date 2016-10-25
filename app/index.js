const querystring = require('querystring')
const readline = require('readline')
const net = require('net')

const query = querystring.parse(location.search.slice(1))
const runtime = require(query.runtime)
const sock = net.connect(Number(query.port))

// read patchs and apply them
const io = readline.createInterface({
  terminal: false,
  input: sock
}).once('line', line => {
  runtime.init(JSON.parse(line))
  io.on('line', line => {
    runtime.mutate(JSON.parse(line))
  })
})

// write an event to the output stream
const send = (event) => {
  if (event.type in event_writers) {
    event_writers[event.type](event)
    sock.write('\n')
  } else {
    console.log(event.type + ' is not implemented')
  }
  event.stopPropagation()
  event.preventDefault()
}

const write_modifiers = (event) => {
  if (event.altKey) sock.write(' alt')
  if (event.ctrlKey) sock.write(' ctrl')
  if (event.shiftKey) sock.write(' shift')
  if (event.metaKey) sock.write(' meta')
}

const write_key_event = (e, type) => {
  sock.write(type + ' [' + dom_path(e.target) + '] ' + e.key)
  write_modifiers(e)
}

const write_button_event = (e, type) => {
  sock.write(type + ' [' + dom_path(e.target) + '] ' + e.button + ' ' + e.x + ' ' + e.y)
}

const top_node = document.lastElementChild

const dom_path = (dom) => {
  const indices = []
  while (dom !== top_node) {
    indices.push(indexOf(dom))
    dom = dom.parentNode
  }
  return indices
}

const indexOf = (dom) => {
  var i = 0
  while (dom.previousSibling) {
    dom = dom.previousSibling
    i += 1
  }
  return i
}

const write_focus_change = (e, type) => {
  if (e.target === window) {
    sock.write(type + ' []')
  } else {
    sock.write(type + ' [' + dom_path(e.target) + ']')
  }
}

const event_writers = {
  keydown(e) { write_key_event(e, 'KeyDown') },
  keyup(e) { write_key_event(e, 'KeyUp') },
  mousemove(e) { sock.write('MouseMove ' + e.x + ' ' + e.y) },
  mouseup(e) { write_button_event(e, 'MouseUp') },
  mousedown(e) { write_button_event(e, 'MouseDown') },
  mouseover(e) { sock.write('MouseOver [' + dom_path(e.target) + ']') },
  mouseout(e) { sock.write('MouseOut [' + dom_path(e.target) + ']') },
  click(e) { write_button_event(e, 'Click') },
  dblclick(e) { write_button_event(e, 'DoubleClick') },
  focus(e) { write_focus_change(e, 'Focus') },
  blur(e) { write_focus_change(e, 'Blur') },
  resize() { sock.write('Resize ' + window.innerWidth + ' ' + window.innerHeight) },
  scroll(e) { sock.write('Scroll [' + dom_path(e.target) + '] ' + window.scrollX + ' ' + window.scrollY) },
}

// Listen to all events
;[
  'click',
  'mousedown',
  'mouseup',
  'dblclick',
  'mousedown',
  'mouseup',
  'mouseover',
  'mousemove',
  'mouseout',
  'dragstart',
  'drag',
  'dragenter',
  'dragleave',
  'dragover',
  'drop',
  'dragend',
  'keydown',
  'keypress',
  'keyup',
  'resize',
  'scroll',
  'select',
  'change',
  'submit',
  'reset',
  'focus',
  'blur',
  'focusin',
  'focusout'
].forEach(event => addEventListener(event, send, true))
