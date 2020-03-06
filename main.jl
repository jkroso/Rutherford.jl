@use "github.com" [
  "MikeInnes/MacroTools.jl" => MacroTools @match
  "jkroso" [
    "DOM.jl" => DOM Node Container Primitive HTML @dom @css_str add_attr [
      "Events.jl" => Events]
    "Prospects.jl" Field assoc push @struct
    "Destructure.jl" @destruct
    "Promises.jl" @defer Deferred need pending Promise
    "DynamicVar.jl" @dynamic!]
  "JunoLab/Atom.jl" => Atom
  "JunoLab/Juno.jl" => Juno]
@use "./transactions" apply Change Assoc Dissoc Delete
import Sockets: listenany, accept, TCPSocket

# Hacks to get completion working with Kip modules
const complete = Atom.handlers["completions"]
Atom.handle("completions") do data
  complete(assoc(data, "mod", getmodule(data["path"])))
end
Atom.getmodule(m::Module) = m
Atom.getmodule(s::AbstractString) = begin
  if occursin('⭒', s)
    for m in values(Kip.modules)
      string(m) == s && return m
    end
  else
    invoke(Atom.getmodule, Tuple{Any}, s)
  end
end

const json = MIME("application/json")

msg(x; kwargs...) = msg(x, kwargs)
# TODO: figure out why I need to buffer the JSON in a String before writing it
msg(x::String, args...) = Atom.isactive(Atom.sock) && println(Atom.sock, repr(json, Any[x, args...]))

const done_task = Task(identity)
done_task.state = :done

"Set the target of keyboard events"
DOM.focus(node::DOM.Node) = begin
  device = current_device()
  if !isnothing(device) && node.attrs[:focus]
    @assert isnothing(device.focused_node) "A node is already focused"
    device.focused_node = node
  else
    node
  end
end

@struct CustomEvent(name::Symbol, path::Events.DOMPath, value::Any) <: Events.Event
Events.name(e::CustomEvent) = e.name
Events.path(e::CustomEvent) = e.path

"""
Event handlers just store the context along with a user defined handler so when the
event occurs it can be handled in the same context the handler assigned in
"""
@struct EventHandler(handler, context)
DOM.wrap_handler(::Symbol, handler) = EventHandler(handler, context[])
DOM.jsonable(::EventHandler) = false

(h::EventHandler)(e) = @dynamic! let context=h.context; invoke_handler(h.handler, e) end
invoke_handler(c::Change, e) = (transact(c); nothing)
invoke_handler(f::Function, e::CustomEvent) = invoke_handler(f, e.value)
invoke_handler(f::Function, e) = begin
  change = f(e)
  change isa Change && transact(change)
  nothing
end

Base.convert(::Type{Node}, p::Promise) = async(p, @dom[:span "Loading..."])
async(p::Promise, pending::Node; onerror=handle_async_error) = begin
  device = current_device()
  n = AsyncNode(true, pending, @async begin
    view = try need(p) catch e onerror(e, device, n) end
    n.iscurrent && msg(device, command="AsyncNode", id=objectid(n), value=view)
    view
  end)
end

handle_async_error(e, _, __) = Base.showerror(stderr, e)

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
    DOM.add_attr(a.pending_view, :id, objectid(a))
  end

DOM.add_attr(a::AsyncNode, key::Symbol, value) = a
DOM.diff(a::AsyncNode, b::AsyncNode) = begin
  a.iscurrent = false # avoid sending messages for out of date promises
  DOM.diff(convert(Primitive, a), convert(Primitive, b))
end

"""
A UI chunk that has some private state associated with it. Component subtypes should
be created with the `@component` macro. e.g `@component SubtypeName`. Because they need
to have certain fields in a certain order

All Components should implement `doodle(<:Component)`
"""
abstract type Component <: DOM.Node end

"Makes it easy to define a new type of Component"
macro component(expr)
  name, state = @match expr begin
    s_(state=x_) => (esc(s), x)
    s_Symbol => (esc(s), nothing)
    _ => error("Incorrect syntax: $expr")
  end
  quote
    Base.@__doc__ mutable struct $name <: Component
      attrs::AbstractDict{Symbol,Any}
      content::Vector{DOM.Node}
      state::Any
      ctx::AbstractContext
      view::Deferred{DOM.Node}
    end
    function $name(attrs, content)
      c = $name(attrs, content, $(esc(state)), context[],
                @defer incontext(draw, c.context)::DOM.Node)
    end
  end
end

incontext(fn, value) = begin
  old = context[]
  context[] = value
  r = Base.invokelatest(fn, value)
  context[] = old
  r
end

"""
Contexts provide infomation about what's being rendered. By specializing methods
on them you can precisly alter the way Components are drawn and how they get/set
the data they depend upon
"""
abstract type AbstractContext end

"Provides access to the current rendering context"
const context = Ref{Union{Nothing,AbstractContext}}(nothing)

"""
A Context is a Component with a linked list of all it's parents
"""
struct Context{Node<:Component,Parent<:AbstractContext} <: AbstractContext
  node::Node
  parent::Parent
end

"""
Make it easier to define complex contexts

```julia
@Context[A B] == Context{A,Context{B,T}} where T
```
"""
macro Context(expr)
  @assert Meta.isexpr(expr, :hcat)
  out = foldr(expr.args, init=esc(:T)) do name, out
    :(Context{$(esc(name)), $out})
  end
  :($out where $(esc(:T)) <: AbstractContext)
end

Base.getindex(parent::AbstractContext, child::Component) = Context(child, parent)

"Get the data associate with a given Context"
data(ctx::Context) = begin
  pd = data(ctx.parent)
  key = path(ctx)
  key == nothing ? pd : get(pd, key)
end

"""
Most of the time getting the data for a component just involves getting the data
of its parent context and refining it by selecting on a key or index. So by default
`data(::Context)` will use this function to determine that key. And in turn this
function looks at the `:key` attribute of the current component.
"""
path(ctx::Context) = path(ctx.node)
path(c::Component) = get(c.attrs, :key, nothing)

add_attr(c::Component, key::Symbol, value::Any) = (c.attrs = add_attr(c.attrs, key, value); c)

DOM.diff(a::T, b::T) where T<:Component = begin
  setfield!(b, :state, a.state)
  DOM.diff(a.view, b.view)
end

Base.convert(::Type{<:DOM.Primitive}, c::Component) = c.view
Base.show(io::IO, m::MIME, c::Component) = show(io, m, c.view)

Base.getproperty(c::Component, f::Symbol) = getproperty(c, Field{f}())
Base.getproperty(c::Component, ::Field{:children}) = c.view.children
Base.getproperty(c::Component, ::Field{:view}) = need(getfield(c, :view))
Base.getproperty(c::Component, ::Field{:context}) = getfield(c, :ctx)[c]

Base.setproperty!(c::Component, f::Symbol, x) = setproperty!(c, Field{f}(), x)
Base.setproperty!(c::Component, ::Field{:state}, x) = begin
  setfield!(c, :state, x)
  schedule_display(c.context)
end

const event_parsers = Dict{String,Function}(
  "mousedown" => d-> Events.MouseDown(d["path"], Events.MouseButton(d["button"]), d["position"]...),
  "mouseup" => d-> Events.MouseUp(d["path"], Events.MouseButton(d["button"]), d["position"]...),
  "mouseover" => d-> Events.MouseOver(d["path"]),
  "mouseout" => d-> Events.MouseOut(d["path"]),
  "click" => d-> Events.Click(d["path"], Events.MouseButton(d["button"]), d["position"]...),
  "dblclick" => d-> Events.DoubleClick(d["path"], Events.MouseButton(d["button"]), d["position"]...),
  "mousemove" => d-> Events.MouseMove(d["path"], d["position"]...),
  "keydown" => d-> Events.KeyDown(UInt8[], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))),
  "keyup" => d-> Events.KeyUp(UInt8[], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))),
  "resize" => d-> Events.Resize(d["width"], d["height"]),
  "scroll" => d-> Events.Scroll(d["path"], d["position"]...))

Atom.handle("event") do id, data
  event = event_parsers[data["type"]](data)
  emit(inline_displays[id], event)
end

Atom.handle("reset module") do file
  delete!(Kip.modules, file)
  getmodule(file)
  nothing
end

@struct Snippet(text::String, line::Int32, path::String, id::Int32)

mutable struct InlineResult
  snippet::Snippet
  state::Symbol
  display_task::Task
  focused_node::Union{Nothing,DOM.Node}
  data::Any
  view::DOM.Node
  InlineResult(s) = new(s, :ok, done_task, nothing)
end

@struct JunoResult(device::InlineResult) <: AbstractContext

msg(::InlineResult, data) = msg(data[:command], data)
data(jr::JunoResult) = jr.device.data

"Get the Module associated with the current file"
getmodule(path) =
  get!(Kip.modules, path) do
    @eval Main module $(Symbol(:⭒, Kip.pkgname(path)))
      using InteractiveUtils
      using Kip
    end
  end

const inline_displays = Dict{Int32,InlineResult}()

Atom.handle("rutherford eval") do results
  Atom.with_logger(Atom.JunoProgressLogger()) do
    lines = Set([x["line"] for x in results])
    total = length(results) + count(d->!(d.snippet.line in lines), values(inline_displays))
    Juno.progress(name="eval") do progress_id
      for (i, data) in enumerate(results)
        @destruct {"text"=>text, "line"=>line, "path"=>path, "id"=>id} = data
        snippet = Snippet(text, line, path, id)
        device = InlineResult(snippet)
        inline_displays[id] = device
        Base.invokelatest(display_result, device, evaluate(device))
        @info "eval" progress=i/total _id=progress_id
      end
      for (i, device) in enumerate(values(inline_displays))
        device.snippet.line in lines && continue
        Base.invokelatest(display_result, device, evaluate(device))
        @info "eval" progress=+(i,length(results))/total _id=progress_id
      end
    end
  end
end

getblocks(data, path) = begin
  @destruct [[start_row, start_col], [end_row, end_col]] = data
  src = String(read(path))
  lines = collect(eachline(path, keep=true))
  if end_col == nothing
    # full file
    start_row = start_col = 1
    end_row = length(lines)
    end_col = length(lines[end])
  else
    # convert JS indexes to JL
    start_row += 1
    start_col += 1
    end_row += 1
    end_col += 1
  end
  start_i = 0
  line = 1
  while line < start_row
    start_i += length(lines[line])
    line += 1
  end
  start_i += start_col
  end_i = start_i
  while line < end_row
    end_i += length(lines[line])
    line += 1
  end
  blocks = Any[]
  while start_i <= end_i
    (ast, i) = Meta.parse(src, start_i)
    line = countlines(IOBuffer(src[1:start_i])) - 1
    text = src[start_i:i-1]
    range = [[line, 0], [line+countlines(IOBuffer(text))-1, 0]]
    push!(blocks, (text=strip(text), line=line, range=range))
    start_i = i
  end
  blocks
end
Atom.handle(getblocks, "getblocks")

evaluate(s::Snippet) =
  lock(Atom.evallock) do
    Atom.withpath(s.path) do
      Atom.@errs include_string(getmodule(s.path), s.text, s.path, s.line)
    end
  end

evaluate(d::InlineResult) = begin
  result = evaluate(d.snippet)
  d.state = result isa Atom.EvalError ? :error : :ok
  result
end

display_result(d::InlineResult, result) = begin
  d.data = result
  schedule_display(d)
end

Base.display(d::InlineResult, view::DOM.Node) = begin
  # update CSS if its stale
  if DOM.css[].state == pending
    msg("stylechange", need(DOM.css[]))
  end
  if isdefined(d, :view)
    patch = DOM.diff(d.view, view)
    patch == nothing || msg("patch", (id=d.snippet.id, patch=patch, state=d.state))
  else
    msg("render", (state=d.state, id=d.snippet.id, dom=view))
  end
  d.view = view
end

Atom.handle("result done") do id
  delete!(inline_displays, id)
end

schedule_display(ctx::Context) = schedule_display(ctx.parent)
schedule_display(jr::JunoResult) = schedule_display(jr.device)
schedule_display(d::InlineResult) = begin
  istaskdone(d.display_task) || return
  d.display_task = @async begin
    d.focused_node = nothing
    try
      # if it ends in a semicolon then the user doesn't want to see the result
      view = if Atom.ends_with_semicolon(d.snippet.text) && d.state == :ok
        @dom[:span class="icon icon-check"]
      else
        incontext(draw, JunoResult(d))
      end
      display(d, view)
    catch e
      showerror(stderr, e)
    end
  end
  nothing
end

"""
Serves as a fallback for `draw()`. If you are implmenting a new datatype or a custom UI
Component for an existing data type then this is the method you should implement
"""
function doodle end

"""
If you want to customise the way a datatype looks in a certain context then this is the
method you need to specialise
"""
function draw end

draw(ctx::AbstractContext) = draw(ctx, data(ctx))
draw(ctx::AbstractContext, data) = doodle(component(ctx), data)
component(::JunoResult) = nothing
component(ctx::Context) = ctx.node
doodle(::Union{Nothing,Component}, data) = doodle(data)

const depth = Ref{Int}(0)
const stop = Ref{Bool}(false)

emit(d::InlineResult, e) = @dynamic! let depth=0, stop=false; emit(d.view, e) end
emit(d::InlineResult, e::Events.Key) = @dynamic! let depth=0, stop=false
  isnothing(d.focused_node) || emit(d.focused_node, e)
end
emit(d::Component, e) = @dynamic! let context = d.context; emit(d.view, e) end
emit(d::Container, e) = begin
  ndepth = depth[] + 1
  path = Events.path(e)
  if length(path) >= ndepth
    child = d.children[path[ndepth]]
    @dynamic! let depth = ndepth; emit(child, e) end
  end
  stop[] && return
  fn = get(d.attrs, Events.name(e), nothing)
  isnothing(fn) ? nothing : fn(e)
end

# Generate a custom event
emit(name::Symbol, value) = begin
  device = current_device()
  node = component(context[])
  path = findpath(device.view, node)
  e = CustomEvent(name, path, value)
  emit(device, e)
end

findpath(parent, target, path=UInt8[]) = begin
  parent === target && return path
  for (i,child) in enumerate(parent.children)
    p = findpath(child, target)
    isnothing(p) || return pushfirst!(p, i)
  end
end

transact(change::Change) = transact(change, context[])
transact(change::Change, ctx::JunoResult) = display_result(ctx.device, apply(change, data(ctx)))
transact(change::Change, ctx::Context) = transact(up(ctx, change), up(ctx))

up(ctx::Context, c::Change) = Assoc(path(ctx), c)
up(ctx::Context, c::Delete) = Dissoc(path(ctx))
up(ctx::Context) = ctx.parent

current_device(ctx=context[]) = top(ctx).device
current_device(::Nothing) = nothing
top(ctx::JunoResult) = ctx
top(ctx::Context) = top(ctx.parent)
