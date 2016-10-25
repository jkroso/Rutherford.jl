const {app, BrowserWindow} = require('electron')
const querystring = require('querystring')
const readline = require('readline')

app.on('window-all-closed', () => {
  if (process.platform != 'darwin') app.quit()
})

const ready = new Promise(resolve => app.on('ready', resolve))

// Create window
readline.createInterface({
  input: process.stdin,
  terminal: false
}).on('line', line => {
  const msg = JSON.parse(line)
  var url = 'file://' + __dirname + '/index.html'
  if ('query' in msg) url += '?' + querystring.encode(msg.query)
  ready.then(() => {
    const window = new BrowserWindow(msg)
    window.loadURL(url)
    if (msg.console) window.openDevTools()
  })
})
