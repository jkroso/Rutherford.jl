@require "github.com/jkroso/DOM.jl" => DOM Events Node Container HTML @dom @css_str
@require "github.com/MikeInnes/MacroTools.jl" => MacroTools @capture postwalk
@require "github.com/jkroso/DynamicVar.jl" @dynamic!
@require "github.com/JunoLab/Atom.jl" => Atom
@require "github.com/jkroso/Electron.jl" App
@require "github.com/jkroso/write-json.jl"
@require "./State" TopLevelCursor UIState cursor currentUI need @handler

import Sockets: listenany, accept, TCPSocket

const app_path = joinpath(@dirname(), "app")
const json = MIME("application/json")
const msglock = ReentrantLock()

msg(x; kwargs...) = msg(x, kwargs)
msg(a::App, data) = msg(a.proc.in, data)
msg(io::IO, data) =
  lock(msglock) do
    show(io, json, data)
    write(io, '\n')
  end

"A Window corresponds to an OS window and can be used to display a UI"
mutable struct Window
  sock::TCPSocket
  view::Node
  UI::Any
  loop::Task
  state::Symbol
end

Window(a::App; kwargs...) = begin
  port, server = listenany(3000)
  initial_view = @dom[:html
    [:head
      [:script "const params=" repr(json, (port=port, runtime=DOM.runtime))]
      [:script "require('$(joinpath(@dirname(), "index.js"))')"]]
    [:body]]

  # tell electron to create a window
  msg(a; title=a.title, kwargs..., html=repr("text/html", initial_view))

  # wait for that window to connect with this process
  sock = accept(server)

  # send events to the UI
  loop = @async for line in eachline(sock)
    DOM.emit(w, Events.parse_event(line))
  end

  w = Window(sock, initial_view, nothing, loop, :ok)
end

Base.wait(e::Window) = fetch(e.loop)
msg(a::Window, data) = msg(a.sock, data)

const done_task = Task(identity)
done_task.state = :done

"""
A UI manages the presentation and manipulation of value. One UI
can be displayed on multiple devices.
"""
mutable struct UI
  view::Node
  render::Any # any callable object
  devices::Vector
  display_task::Task
  data::TopLevelCursor
  private::Dict{Vector{Any},Dict{Any,Any}}
end

UI(fn, data) = begin
  ui = UI(DOM.null_node, fn, [], done_task, TopLevelCursor(data), Dict())
  push!(getfield(ui.data, :UIs), ui)
  ui
end

DOM.emit(ui::UI, e::Events.Event) = begin
  @dynamic! let currentUI = ui, cursor = ui.data
    @static if isinteractive()
      Base.invokelatest(DOM.emit, ui.view, e)
    else
      DOM.emit(ui.view, e)
    end
  end
end

msg(ui::UI, data) = foreach(d->msg(d, data), ui.devices)

"""
Connect a Window with a UI so that the UI can render to the window
and the window can send events to the UI for it to handle
"""
couple(w::Window, ui::UI) = begin
  @assert w.UI == nothing "This window is already coupled with a UI"
  w.UI = ui
  push!(ui.devices, w)
  display(w, ui)
end

decouple(w::Window, ui::UI) = begin
  w.UI = nothing
  deleteat!(ui.devices, findfirst(ui.devices, w))
end

"Generate a DOM view using the UI's current state"
render(ui::UI) = @dynamic! let currentUI = ui, cursor = ui.data
  ui.render(need(ui.data))
end

"""
Defining methods that render cursors directly is too verbose. So this method places the cursor on
the dynamic variable `cursor` and calls `render` with the unwrapped value
"""
render(c::UIState) = @dynamic! let cursor = c
  render(need(c))
end

Base.display(ui::UI) = begin
  istaskdone(ui.display_task) || return
  ui.display_task = @async begin
    state = need(ui.data) isa Atom.EvalError ? :error : :ok
    view = Atom.@errs render(ui)
    try
      if view isa Atom.EvalError
        state = :error
        ui.view = render(view)
      else
        ui.view = view
      end
      for device in ui.devices
        device.state = state
        display(device, ui.view)
      end
    catch e
      @show e
    end
  end
end

Base.display(w::Window, ui::UI) = begin
  ui.view = render(ui)
  display(w, ui.view)
end

Base.display(w::Window, view::Node) = begin
  # wrap the view because DOM expects it to be a proper HTML document
  wrapped = @dom[HTML view]
  patch = DOM.diff(w.view, wrapped)
  patch == nothing || msg(w, patch)
  w.view = wrapped
  nothing
end

DOM.emit(w::Window, e::Events.Event) =
  @dynamic! let currentUI = w.UI, cursor = w.UI.data
    DOM.emit(w.view, e)
  end

async(fn::Function, pending::Node; onerror=handle_async_error) = begin
  ui = currentUI[] # deref here because we are using @dynamic! rather than @dynamic
  n = AsyncNode(true, pending, @async begin
    view = try need(fn()) catch e onerror(e, ui, n) end
    n.iscurrent && msg(ui, command="AsyncNode", id=objectid(n), value=view)
    view
  end)
end

handle_async_error(e, _, __) = Base.showerror(stderr, e)

mutable struct AsyncNode <: Node
  iscurrent::Bool
  pending_view::Node
  task::Task
end

Base.show(io::IO, m::MIME"application/json", a::AsyncNode) = show(io, m, convert(Container, a))
Base.convert(::Type{Container}, a::AsyncNode) =
  if istaskdone(a.task)
    Base.task_result(a.task)
  else
    DOM.add_attr(a.pending_view, :id, objectid(a))
  end

DOM.add_attr(a::AsyncNode, key::Symbol, value) = a
DOM.diff(a::AsyncNode, b::AsyncNode) = begin
  a.iscurrent = false # avoid sending messages for out of date promises
  DOM.diff(convert(Container, a), convert(Container, b))
end

"""
Extends the `@dom` macro to provide special syntax for cursor scope refinement

```julia
@dom[TextField → :input]
```
"""
macro ui(expr)
  expr = macroexpand(__module__, Expr(:macrocall, getfield(DOM, Symbol("@dom")), __source__, expr))
  expr = postwalk(expr) do x
    if @capture(x, (f_ → key_)(attrs_, children_))
      :($scoped($f, $key, $attrs, $children))
    else
      x
    end
  end
  esc(expr)
end

scoped(fn, key, attrs, children) = begin
  c = cursor[][key]
  @dynamic! let cursor = c
    if applicable(fn, attrs, children)
      fn(attrs, children)
    else
      fn(attrs, children, need(c))
    end
  end
end

export @ui, @handler, @css_str, cursor, render
