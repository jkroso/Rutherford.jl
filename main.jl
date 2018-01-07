@require "github.com/MikeInnes/MacroTools.jl" => MacroTools @match @capture
@require "github.com/jkroso/DOM.jl" => DOM Events Node Container @dom
@require "github.com/jkroso/Promises.jl" Promise failed
@require "github.com/jkroso/DynamicVar.jl" @dynamic!
@require "github.com/jkroso/Electron.jl" App
@require "github.com/jkroso/write-json.jl"
@require "./State.jl" State Cursor need state

@dynamic! currentUI = nothing
const app_path = joinpath(@dirname(), "app")
const json = MIME("application/json")
const msglock = ReentrantLock()

msg(a::App, data) = msg(a.stdin, data)
msg(io::IO, data) = begin
  lock(msglock)
  show(io, json, data)
  write(io, '\n')
  unlock(msglock)
end

"A Window corresponds to an OS window and can be used to display a UI"
mutable struct Window
  sock::TCPSocket
  view::Node
  UI::Any
  loop::Task
end

Window(a::App; kwargs...) = begin
  port, server = listenany(3000)
  initial_view = @dom [:html
    [:head
      [:script "const params=" stringmime(json, Dict(:port=>port,:runtime=>DOM.runtime))]
      [:script "require('$(joinpath(@dirname(), "index.js"))')"]]
    [:body]]

  # tell electron to create a window
  msg(a, Dict(:title => a.title,
              Dict(kwargs)...,
              :html => stringmime("text/html", initial_view)))

  # wait for that window to connect with this process
  sock = accept(server)

  # send events to the UI
  loop = @schedule for line in eachline(sock)
    DOM.emit(w.UI, Events.parse_event(line))
  end

  w = Window(sock, initial_view, nothing, loop)
end

Base.wait(e::Window) = wait(e.loop)
msg(a::Window, data) = msg(a.sock, data)

const done_task = Task(identity)
done_task.state = :done

"""
An UI manages the presentation and manipulation of a State object. One UI
can be displayed on multiple devices.
"""
mutable struct UI
  view::Node
  render::Any # any callable object
  devices::Vector
  display_task::Task
  state::State
  UI(fn) = new(DOM.null_node, fn, [], done_task)
  UI(fn, data) = begin
    ui = UI(fn)
    couple(ui, State(data, []))
    ui
  end
end

DOM.emit(ui::UI, e::Events.Event) =
  @static if isinteractive()
    Base.invokelatest(DOM.emit, ui.view, e)
  else
    DOM.emit(ui.view, e)
  end
msg(ui::UI, data) = foreach(d->msg(d, data), ui.devices)

"""
Like display(a, b) but will also create any connections necessary in order
to make the displayed UI interactive
"""
couple(a, b) = display(a, b)

"""
Connect a UI object with a State object so that when the state changes
it triggers an update to the UI
"""
couple(ui::UI, s::State) = begin
  ui.state = s
  push!(s.UIs, ui)
end

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
render(ui::UI) =
  @dynamic! let state = ui.state, currentUI = ui
    ui.render(need(ui.state))
  end

Base.display(ui::UI) = begin
  istaskdone(ui.display_task) || return
  ui.display_task = @schedule begin
    ui.view = render(ui)
    for device in ui.devices
      display(device, ui.view)
    end
  end
end

Base.display(w::Window, ui::UI) = begin
  ui.view = render(ui)
  display(w, ui.view)
end

Base.display(w::Window, view::Node) = begin
  patch = DOM.diff(w.view, view)
  isnull(patch) || msg(w, patch)
  w.view = view
  nothing
end

window(a::App, ui::UI, data) = window(a, ui, State(data, []))
window(fn::Function, a::App, data) = window(a, UI(fn), data)
window(a::App, ui::UI, state::State) = begin
  w = Window(a)
  couple(ui, state)
  couple(w, ui)
  w
end

mutable struct AsyncNode <: Node
  promise::Promise
  current::Bool
end

Base.convert(::Type{Node}, p::Promise) = begin
  @schedule try wait(p) catch e
    Base.showerror(STDERR, e)
  finally
    n.current && msg(ui, Dict(:command => "AsyncPromise",
                              :id => object_id(p),
                              :iserror => p.state == failed,
                              :value => convert(Node, p.state == failed ? p.error : p.value)))
  end
  ui = currentUI[] # deref here because we are using @dynamic! rather than @dynamic
  n = AsyncNode(p, true)
end

Base.show(io::IO, m::MIME"application/json", a::AsyncNode) =
  show(io, m, @dom [:div id=object_id(a.promise)])

DOM.add_attr(a::AsyncNode, key::Symbol, value) = a
DOM.diff(a::AsyncNode, b::AsyncNode) = begin
  a.current = false # avoid sending messages for out of date promises
  a.promise === b.promise && return Nullable{DOM.Patch}()
  DOM.Replace(b) |> Nullable{DOM.Patch}
end

"A UI chunk that has some ephemeral state associated with it"
abstract type Component <: Node end

"Define a new subtype of Component"
macro component(name)
  :(mutable struct $(esc(name)) <: Component
    args::Any
    essential::Any
    UI::Any
    ephemeral::Any
    view::Node
    $(esc(name))(args...) = new(args, state[], currentUI[])
  end)
end

DOM.diff(a::T, b::T) where T<:Component = begin
  b.ephemeral = a.ephemeral
  DOM.diff(render(a), render(b))
end

default_data(::Component) = Dict()

DOM.emit(c::Component, e) = DOM.emit(c.view, e)
# needed by emit
Base.convert(::Type{Container}, c::Component) = render(c)

render(c::Component) = begin
  isdefined(c, :view) && return c.view
  isdefined(c, :ephemeral) || (c.ephemeral = default_data(c))
  @dynamic! let state = c.essential, currentUI = c.UI
    c.view = render(c, c.args...)
  end
end

set_state(c::Component, state) = begin
  c.ephemeral = state
  display(c.UI)
end

Base.show(io::IO, m::MIME, c::Component) = show(io, m, render(c))
