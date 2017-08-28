@require "github.com/jkroso/DOM.jl" => DOM Events emit @dom
@require "github.com/jkroso/Electron.jl" App
@require "github.com/jkroso/Cursor.jl" Cursor
@require "github.com/jkroso/write-json.jl"
@require "github.com/jkroso/Port.jl" Port

const app_path = joinpath(@dirname(), "app")
const json = MIME("application/json")

mutable struct Window
  data::Port
  currentUI::DOM.Node
  server::Base.TCPServer
  sock::TCPSocket
  onclose::Condition
  eventLoop::Task
  renderLoop::Task
  currentCursor::Cursor
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
    @static if isinteractive()
      # saves world age problems
      Base.invokelatest(emit, w, Events.parse_event(line))
    else
      emit(w, Events.parse_event(line))
    end
  end

  w.renderLoop = @schedule for cursor in w.data
    @static if isinteractive()
      Base.invokelatest(render, w, cursor)
    else
      render(w, cursor)
    end
  end

  render(w, Cursor(data, w.data))

  w
end

"Rerender the window using its current data"
render(w::Window) = display(w, convert(DOM.Container{:html}, w.currentCursor))

"Render the window with new data"
render(w::Window, c::Cursor) = begin
  w.currentCursor = c
  display(w, convert(DOM.Container{:html}, c))
end

Base.wait(w::Window) = waitany(w.onclose, w.eventLoop, w.renderLoop)
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

emit(w::Window, e::Events.Event) = emit(w.currentUI, e)

export App, Window
