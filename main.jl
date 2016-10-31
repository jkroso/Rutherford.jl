@require "github.com/jkroso/DOM.jl" diff runtime Events dispatch Node Container
@require "github.com/jkroso/Electron.jl" install
@require "github.com/jkroso/Cursor.jl" Cursor
@require "github.com/jkroso/write-json.jl"
@require "github.com/jkroso/parse-json.jl"
@require "github.com/jkroso/Port.jl" Port

const app_path = joinpath(@dirname(), "app")
const json_mime = MIME("application/json")

type Window
  ready::Condition
  events::Port
  data::Port
  renderLoop::Task
  currentUI::Node
  Window() = new(Condition(), Port(), Port())
end

type App
  title::String
  stdin::IO
  proc::Base.Process
end

App(title; version=v"1.4.4") = App(title, open(`$(install(version)) $app_path`, "w")...)

Window(a::App, data; kwargs...) = begin
  window = Window()
  port,server = listenany(3000)
  show(a.stdin, json_mime, Dict(:title=>a.title,
                                Dict(kwargs)...,
                                :query=>Dict(:port=>port, :runtime=>runtime)))
  write(a.stdin, '\n')

  # connect with the window
  sock = accept(server)

  window.renderLoop = @schedule try
    # Send over initial screen
    window.currentUI = convert(Container{:html}, Cursor(data, window.data))
    show(sock, json_mime, window.currentUI)
    write(sock, '\n')
    notify(window.ready)

    # Write patches
    for cursor in window.data
      nextGUI = convert(Container{:html}, cursor)
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
  @schedule begin
    wait(window.ready)
    for line in eachline(sock)
      e = Events.parse_event(line)
      dispatch(window, e)
      put!(window.events, e)
    end
  end

  return window
end

Base.wait(w::Window) = wait(w.renderLoop)
Base.wait(a::App) = wait(a.proc)

dispatch(w::Window, e::Events.Event) = dispatch(w.currentUI, e)
