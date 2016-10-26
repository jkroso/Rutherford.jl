@require "github.com/jkroso/DOM.jl/Events" => Events
@require "github.com/jkroso/DOM.jl" diff runtime
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
end

type App
  title::AbstractString
  stdin::IO
  proc::Base.Process
end

App(title; version=v"1.4.4") = App(title, open(`$(install(version)) $app_path`, "w")...)

Window(a::App, params::Associative) = begin
  port,server = listenany(3000)
  params = Dict(:title=>a.title, params..., :query=>Dict(:port=>port, :runtime=>runtime))
  ui_port = Port()
  show(a.stdin, json_mime, params)
  write(a.stdin, '\n')

  # connect with the window
  sock = accept(server)

  renderLoop = @schedule try
    currentGUI = take!(ui_port)

    # Send over initial rendering
    show(sock, json_mime, currentGUI)
    write(sock, '\n')

    # Write patches
    while isopen(ui_port)
      nextGUI = take!(ui_port)
      patch = diff(currentGUI, nextGUI)
      isnull(patch) && continue
      show(sock, json_mime, patch)
      write(sock, '\n')
      currentGUI = nextGUI
    end
  finally
    close(server)
  end

  # Produce a series of events
  output = @task for line in eachline(sock)
    produce(Events.parse_event(line))
  end

  sleep(0) # allow tasks to get started
  Window(ui_port, output, renderLoop)
end

Base.wait(w::Window) = wait(w.renderLoop)
Base.wait(a::App) = wait(a.proc)
