@require "github.com/MikeInnes/MacroTools.jl" => MacroTools @match @capture
@require "github.com/jkroso/DOM.jl" => DOM Events Node Container Primitive HTML @dom
@require "github.com/jkroso/Prospects.jl/deftype" deftype
@require "github.com/jkroso/DynamicVar.jl" @dynamic!
@require "github.com/jkroso/Prospects.jl" assoc
@require "github.com/jkroso/Electron.jl" App
@require "github.com/jkroso/write-json.jl"
@require "./State.jl" State need state

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
    DOM.emit(w, Events.parse_event(line))
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
  # wrap the view because DOM expects it to be a proper HTML document
  wrapped = @dom [HTML view]
  patch = DOM.diff(w.view, wrapped)
  isnull(patch) || msg(w, patch)
  w.view = wrapped
  nothing
end

DOM.emit(w::Window, e::Events.Event) = DOM.emit(w.view, e)

async(fn::Function, pending::Node; onerror=handle_async_error) = begin
  ui = currentUI[] # deref here because we are using @dynamic! rather than @dynamic
  n = AsyncNode(true, pending, @schedule begin
    view = try need(fn()) catch e onerror(e, ui, n) end
    n.iscurrent && msg(ui, Dict(:command => "AsyncNode",
                                :id => object_id(n),
                                :value => view))
    view
  end)
end

handle_async_error(e, _, __) = Base.showerror(STDERR, e)

mutable struct AsyncNode <: Node
  iscurrent::Bool
  pending_view::Node
  task::Task
end

Base.show(io::IO, m::MIME"application/json", a::AsyncNode) = show(io, m, convert(Primitive, a))
Base.convert(::Type{Primitive}, a::AsyncNode) =
  if istaskdone(a.task)
    Base.task_result(a.task)
  else
    DOM.add_attr(a.pending_view, :id, object_id(a))
  end

DOM.add_attr(a::AsyncNode, key::Symbol, value) = a
DOM.diff(a::AsyncNode, b::AsyncNode) = begin
  a.iscurrent = false # avoid sending messages for out of date promises
  DOM.diff(convert(Primitive, a), convert(Primitive, b))
end

"A UI chunk that has some ephemeral state associated with it"
abstract type Component <: Node end

"Define a new subtype of Component"
macro component(expr)
  @capture expr name_(args__)
  state_name = Symbol(name, "State")
  quote
    $(deftype(:($state_name($(args...))), false))
    default_state = $(esc(state_name))()
    mutable struct $(esc(name)) <: Component
      args::Any
      essential::Any
      UI::Any
      ephemeral::$(esc(state_name))
      view::Node
      $(esc(name))(args...) = new(args, state[], currentUI[], default_state)
    end
  end
end

DOM.diff(a::T, b::T) where T<:Component = begin
  b.ephemeral = a.ephemeral
  DOM.diff(render(a), render(b))
end

DOM.emit(c::Component, e) = DOM.emit(c.view, e)
# needed by emit
Base.convert(::Type{Container}, c::Component) = render(c)

render(c::Component) = begin
  isdefined(c, :view) && return c.view
  @dynamic! let state = c.essential, currentUI = c.UI
    c.view = render(c, c.args...)
  end
end

getstate(c::Component) = c.ephemeral
setstate(c::Component, key, state) = setstate(c, assoc(getstate(c), key, state))
setstate(c::Component, state) = begin
  c.ephemeral = state
  display(c.UI)
end

Base.show(io::IO, m::MIME, c::Component) = show(io, m, render(c))
