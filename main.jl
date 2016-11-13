@require "github.com/jkroso/DOM.jl" => DOM Events dispatch @dom
@require "github.com/jkroso/Electron.jl" App
@require "github.com/jkroso/Cursor.jl" Cursor
@require "github.com/jkroso/write-json.jl"
@require "github.com/jkroso/Port.jl" Port

const app_path = joinpath(@dirname(), "app")
const json = MIME("application/json")

type Window
  data::Port
  currentUI::DOM.Node
  server::Base.TCPServer
  sock::TCPSocket
  onclose::Condition
  eventLoop::Task
  renderLoop::Task
  Window(ui, server, sock) = new(Port(), ui, server, sock, Condition())
end

Window(a::App, data=nothing; kwargs...) = begin
  port, server = listenany(3000)
  initial_UI = @dom [:html
    [:head
      [:script "const params=" stringmime("application/json", Dict(:port=>port,:runtime=>DOM.runtime))]
      [:script "require('$(joinpath(@dirname(), "index.js"))')"]]
    [:body]]
  html = stringmime("text/html", initial_UI)

  show(a.stdin, json, Dict(:title=>a.title, Dict(kwargs)..., :html=>html))
  write(a.stdin, '\n')

  # connect with the window
  w = Window(initial_UI, server, accept(server))

  # Produce a series of events
  w.eventLoop = @schedule for line in eachline(w.sock)
    dispatch(w, Events.parse_event(line))
  end

  w.renderLoop = @schedule for cursor in w.data
    display(w, convert(DOM.Container{:html}, cursor))
  end

  display(w, convert(DOM.Container{:html}, Cursor(data, w.data)))

  w
end

Base.wait(w::Window) = waitany(w.onclose, w.eventLoop, w.renderloop)
Base.wait(a::App) = wait(a.proc)
Base.close(w::Window) = close(w.server)

Base.display(w::Window, nextUI::DOM.Node) = begin
  patch = DOM.diff(w.currentUI, nextUI)
  if !isnull(patch)
    show(w.sock, json, patch)
    write(w.sock, '\n')
  end
  w.currentUI = nextUI
  nothing
end

dispatch(w::Window, e::Events.Event) = dispatch(w.currentUI, e)

export App, Window
