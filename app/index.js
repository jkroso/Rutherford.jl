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
