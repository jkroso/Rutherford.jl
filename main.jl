@require "github.com/jkroso/DOM.jl" diff runtime Events dispatch Node
@require "/Users/jkroso/Projects/JuliaLang/Cursor.jl" TopLevelCursor
@require "github.com/jkroso/Electron.jl" install
@require "github.com/jkroso/write-json.jl"
@require "github.com/jkroso/parse-json.jl"
@require "github.com/jkroso/Port.jl" Port

const json_mime = MIME("application/json")
const app_path = joinpath(@dirname(), "app")

type Window
  ui::Port
  events::Task
  renderLoop::Task
  currentUI::Node
  Window() = new(Port())
end

type App
  title::String
  stdin::IO
  proc::Base.Process
end

App(title; version=v"1.4.4") = App(title, open(`$(install(version)) $app_path`, "w")...)

Window(a::App, params::Associative) = begin
  window = Window()
  port,server = listenany(3000)
  params = Dict(:title=>a.title, params..., :query=>Dict(:port=>port, :runtime=>runtime))
  show(a.stdin, json_mime, params)
  write(a.stdin, '\n')

  # connect with the window
  sock = accept(server)

  window.renderLoop = @schedule try
    # Send over initial rendering
    window.currentUI = take!(window.ui)
    show(sock, json_mime, window.currentUI)
    write(sock, '\n')

    # Write patches
    for nextGUI in window.ui
      patch = diff(window.currentUI, nextGUI)
      isnull(patch) && continue
      show(sock, json_mime, patch)
      write(sock, '\n')
      window.currentUI = nextGUI
    end
  finally
    close(server)
  end

  # Produce a series of events
  window.events = @task for line in eachline(sock)
    e = Events.parse_event(line)
    dispatch(window, e)
    produce(e)
  end

  sleep(0) # allow tasks to get started
  return window
end

Base.wait(w::Window) = wait(w.renderLoop)
Base.wait(a::App) = wait(a.proc)
Base.put!(w::Window, n) = put!(w.ui, n)

dispatch(w::Window, e::Events.Event) = dispatch(w.currentUI, e)

"""
Starts a rendering loop where the return value of each iteration becomes the
UI of the window. It wraps your data in a `Cursor` which enables you to treat
immutable data almost as if it was mutable.
"""
loop(render::Function, w::Window, initial_data) = begin
  c = TopLevelCursor(initial_data, Port())
  @schedule for cursor in c.port
    put!(w, render(cursor))
  end
  # let loop start before puting
  @schedule put!(c.port, c)
  c.port
end