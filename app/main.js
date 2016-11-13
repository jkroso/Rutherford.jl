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
  ready.then(() => {
    const window = new BrowserWindow(msg)
    if (msg.console) window.openDevTools()
    window.loadURL(`data:text/html,<!DOCTYPE html>${msg.html}`)
  })
})
