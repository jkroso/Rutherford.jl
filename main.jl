@require "github.com/jkroso/DOM.jl" => DOM Replace Events add_attr exports...
@require "github.com/jkroso/Promises.jl" Promise failed
@require "github.com/jkroso/Electron.jl" App
@require "github.com/jkroso/Cursor.jl" Cursor
@require "github.com/jkroso/write-json.jl"
@require "github.com/jkroso/Port.jl" Port

const app_path = joinpath(@dirname(), "app")
const json = MIME("application/json")

const msglock = ReentrantLock()
msg(io::IO, data) = begin
  lock(msglock)
  show(io, json, data)
  write(io, '\n')
  unlock(msglock)
end

mutable struct Window
  data::Port
  currentUI::DOM.Node
  server::Base.TCPServer
  sock::TCPSocket
  eventLoop::Task
  renderLoop::Task
  currentCursor::Cursor
  Window(ui, server, sock) = new(Port(), ui, server, sock)
end

Window(a::App, data=nothing; kwargs...) = begin
  port, server = listenany(3000)
  initial_UI = @dom [:html
    [:head
      [:script "const params=" stringmime(json, Dict(:port=>port,:runtime=>DOM.runtime))]
      [:script "require('$(joinpath(@dirname(), "index.js"))')"]]
    [:body]]

  msg(a.stdin, Dict(:title=>a.title, Dict(kwargs)..., :html=>stringmime("text/html", initial_UI)))

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
render(w::Window) = render(w, w.currentCursor)
"Render the window with new data"
render(w::Window, c::Cursor) = begin
  w.currentCursor = c
  task_local_storage(:window, w) do
    display(w, convert(DOM.Container{:html}, c))
  end
end

Base.wait(w::Window) = wait(w.eventLoop)
Base.wait(a::App) = wait(a.proc)
Base.close(w::Window) = close(w.server)

Base.display(w::Window, nextUI::Node) = begin
  patch = diff(w.currentUI, nextUI)
  isnull(patch) || msg(w.sock, patch)
  w.currentUI = nextUI
  nothing
end

emit(w::Window, e::Events.Event) = emit(w.currentUI, e)

mutable struct AsyncNode <: Node
  promise::Promise
  current::Bool
end

Base.convert(::Type{Node}, p::Promise) = begin
  w = task_local_storage(:window)
  n = AsyncNode(p, true)
  @schedule try wait(p) catch e
    Base.showerror(STDERR, e)
  finally
    if n.current
      msg(w.sock, Dict(:command => "AsyncPromise",
                       :id => object_id(p),
                       :iserror => p.state == failed,
                       :value => convert(Node, p.state == failed ? p.error : p.value)))
    end
  end
  n
end

Base.convert(::Type{DOM.Primitive}, a::AsyncNode) = begin
  @dom [:div id=object_id(a.promise)]
end

add_attr(a::AsyncNode, key::Symbol, value) = a
diff(a::AsyncNode, b::AsyncNode) = begin
  a.current = false
  a.promise === b.promise && return Nullable{Patch}()
  if isready(a.promise)
    DOM.SetAttribute(:id, object_id(b.promise))
  else
    DOM.Replace(convert(Primitive, b))
  end |> Nullable{Patch}
end

export App, Window
