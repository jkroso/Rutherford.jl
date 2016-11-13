const runtime = require(params.runtime)
const readline = require('readline')
const net = require('net')

const sock = net.connect(Number(params.port))

// read patchs and apply them
readline.createInterface({
  terminal: false,
  input: sock
}).on('line', line => runtime.mutate(JSON.parse(line)))

// write an event to the output stream
const send = (event) => {
  runtime.write_event(sock, event)
  event.stopPropagation()
  event.preventDefault()
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
