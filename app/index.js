var readline = require('readline')
var net = require('net')

var port = Number(location.search.slice(6))
var sock = net.connect(port)

var node

// read patchs and apply them
readline.createInterface({
  terminal: false,
  input: sock
}).on('line', function(line){
  patch = JSON.parse(line)
  if (node) {
    node.applyPatch(patch)
  } else {
    node = new Patchwork.Node('root', patch)
  }
})

// write an event to the output stream
function send(event) {
  sock.write(JSON.stringify({type:event.type}) + '\n')
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
].forEach(function(event){
  window.addEventListener(event, send, true)
})
