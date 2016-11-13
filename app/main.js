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
  const {id,html} = msg
  ready.then(() => {
    const window = new BrowserWindow(msg)
    if (msg.console) window.openDevTools()
    window.on('closed', () => process.stdout.write('closed ' + id + '\n'))
    window.loadURL(`data:text/html,<!DOCTYPE html>${html}`)
  })
})
