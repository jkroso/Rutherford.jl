var querystring = require('querystring')
var Window = require('browser-window')
var readline = require('readline')
var app = require('app')

app.on('window-all-closed', function(){
  if (process.platform != 'darwin') app.quit()
})

var ready = new Promise(function(resolve){ app.on('ready', resolve) })

// global so it won't be GC'ed
var window

// Create window asked
readline.createInterface({
  input: process.stdin,
  terminal: false
}).on('line', function(line){
  var msg = JSON.parse(line)
  ready.then(function(){
    var url = 'file://' + __dirname + '/index.html'
    if ('query' in msg) url += '?' + querystring.encode(msg.query)
    window = new Window(msg)
    window.loadUrl(url)
    if (msg.console) window.openDevTools()
  })
})
