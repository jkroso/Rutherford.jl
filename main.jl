@use "github.com" [
  "MikeInnes/MacroTools.jl" => MacroTools @match
  "jkroso" [
    "DOM.jl" => DOM Node Container Primitive @dom @css_str ["Events.jl" => Events]
    "Prospects.jl" Field assoc push @struct
    "Destructure.jl" @destruct
    "Promises.jl" @defer Deferred need pending Promise
    "DynamicVar.jl" @dynamic!
    "Unparse.jl" serialize]
  "JunoLab/Atom.jl" => Atom
  "JunoLab/Juno.jl" => Juno]
@use "./transactions" apply Change Assoc Dissoc Delete

# Hacks to get completion working with Kip modules
const complete = Atom.handlers["completions"]
Atom.handle("completions") do data
  mod = Kip.get_module(data["path"], interactive=true)
  complete(assoc(data, "mod", mod))
end
Atom.getmodule(m::Module) = m
Atom.getmodule(s::AbstractString) = begin
  s = replace(s, r"…$"=>"") # if the name is long it will be elided
  if occursin('⭒', s)
    for m in values(Kip.modules)
      startswith(string(m), s) && return m
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
@struct EventHandler(handler, context, intent)
DOM.wrap_handler(::Symbol, handler) = EventHandler(handler, context[], intent[])
DOM.jsonable(::EventHandler) = false

(h::EventHandler)(e) = @dynamic! let context=h.context, intent=h.intent; invoke_handler(h.handler, e) end
invoke_handler(c::Change, e) = (transact(c); nothing)
invoke_handler(f::Function, e::CustomEvent) = invoke_handler(f, e.value)
invoke_handler(f::Function, e) = begin
  change = f(e)
  change isa Change && transact(change)
  nothing
end

Base.convert(::Type{Node}, p::Promise) = async(p, @dom[:span "Loading..."])
handle_async_error(e, _, __) = Base.showerror(stderr, e)
async(p::Promise, pending::Node; onerror=handle_async_error) = begin
  device = current_device()
  n = AsyncNode(true, pending, @async begin
    view = try need(p) catch e onerror(e, device, n) end
    n.iscurrent && msg("AsyncNode", id=objectid(n), value=view)
    view
  end)
end

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
A UI chunk that might have some private state associated with it. Component subtypes should
be created with the `@component` macro. e.g `@component SubtypeName`. Because they need to
have certain fields in a certain order
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
      intent::Intent
      view::Deferred{DOM.Node}
    end
    function $name(attrs, content)
      c = $name(attrs, content, $(esc(state)), context[], intent[],
                @defer(@dynamic!(let context = c.context, intent = c.intent
                  Base.invokelatest(draw, c.intent, c.context, data(c.context))
                end)::DOM.Node))
    end
  end
end

"""
Contexts provide infomation about the location in the UI where the current thing
been drawn will be shown
"""
abstract type AbstractContext end

"Provides access to the current rendering context"
const context = Ref{Union{AbstractContext,Nothing}}(nothing)

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

DOM.add_attr(c::Component, key::Symbol, value::Any) = begin
  c.attrs = DOM.add_attr(c.attrs, key, value)
  c
end

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
  if haskey(inline_displays, id)
    res = Atom.@errs emit(inline_displays[id], event)
    res isa Atom.EvalError && showerror(IOContext(stderr, :limit => true), res)
  end
  nothing
end

Atom.handle("reset module") do file
  delete!(Kip.modules, file)
  Kip.get_module(file, interactive=true)
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

"Intents describe what the user is trying to do with the data"
abstract type Intent end
@struct View() <: Intent
@struct Edit() <: Intent

@struct TopLevelContext(device::InlineResult) <: AbstractContext
data(c::TopLevelContext) = c.device.data

Base.getproperty(c::AbstractContext, f::Symbol) = getproperty(c, Field{f}())
Base.getproperty(c::Context, ::Field{:component}) = getfield(c, :node)
Base.getproperty(::TopLevelContext, ::Field{:component}) = nothing

"Provides access to the current rendering Intent"
const intent = Ref{Union{Intent, Nothing}}(nothing)

const inline_displays = Dict{Int32,InlineResult}()

Atom.handle("rutherford eval") do blocks
  Atom.with_logger(Atom.JunoProgressLogger()) do
    lines = Set([x["line"] for x in blocks])
    total = length(blocks) + count(d->!(d.snippet.line in lines), values(inline_displays))
    Juno.progress(name="eval") do progress_id
      for (i, data) in enumerate(blocks)
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
        @info "eval" progress=+(i,length(blocks))/total _id=progress_id
      end
    end
  end
end

getblocks(data, path, src) = begin
  @destruct [[start_row, start_col], [end_row, end_col]] = data
  lines = collect(eachline(IOBuffer(src), keep=true))
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

const evallock = ReentrantLock()
evaluate(s::Snippet) =
  lock(evallock) do
    Atom.withpath(s.path) do
      m = Kip.get_module(s.path, interactive=true)
      res = Atom.@errs include_string(m, s.text, s.path, s.line)
      res isa Atom.EvalError && showerror(IOContext(stderr, :limit => true), res)
      res
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
schedule_display(jr::TopLevelContext) = schedule_display(jr.device)
schedule_display(d::InlineResult) = begin
  istaskdone(d.display_task) || return
  d.display_task = @async begin
    d.focused_node = nothing
    try
      # if it ends in a semicolon then the user doesn't want to see the result
      view = if Atom.ends_with_semicolon(d.snippet.text) && d.state == :ok
        @dom[:span class="icon icon-check"]
      else
        @dynamic! let context = TopLevelContext(d), intent = choose_intent(d)
          Base.invokelatest(draw, intent[], context[], d.data)
        end
      end
      display(d, view)
    catch e
      showerror(stderr, e)
    end
  end
  nothing
end

choose_intent(d::InlineResult, data=d.data) = View()
choose_intent(d::InlineResult, data::Union{String,Dict}) = Edit()

"used to tell emit() to stop recursion"
const stop = Ref{Bool}(false)

emit(d::InlineResult, e) = @dynamic! let stop=false; emit(d, e, 1) end
emit(d::InlineResult, e, i) = emit(d.view, e, i)
emit(d::InlineResult, e::Events.Key, i) = isnothing(d.focused_node) || emit(d.focused_node, e, i)
emit(d::Component, e, i) = @dynamic! let context = d.context; emit(d.view, e, i) end
emit(d::Container, e, i) = begin
  path = Events.path(e)
  if length(path) >= i
    child = d.children[path[i]]
    emit(child, e, i + 1)
  end
  stop[] && return
  fn = get(d.attrs, Events.name(e), nothing)
  isnothing(fn) ? nothing : fn(e)
end

# Generate a custom event
emit(name::Symbol, value) = begin
  device = current_device()
  path = findpath(device.view, context[].component)
  e = CustomEvent(name, path, value)
  emit(device, e)
end

findpath(parent::DOM.Text, target, path) = nothing
findpath(parent, target, path=UInt8[]) = begin
  parent === target && return path
  for (i,child) in enumerate(parent.children)
    p = findpath(child, target, path)
    isnothing(p) || return pushfirst!(p, i)
  end
end

transact(change::Change) = transact(intent[], context[], change)
transact(i::Intent, ctx::Context, change::Change) = transact(i, up(ctx), up(ctx, change))
transact(::View, ctx::TopLevelContext, change::Change) = display_result(ctx.device, apply(change, data(ctx)))
transact(::Edit, ctx::TopLevelContext, change::Change) = begin
  @destruct {path, line, id} = ctx.device.snippet
  d = apply(change, data(ctx))
  src = serialize(d, width=100, mod=Kip.get_module(path))
  Atom.@msg edit(src, line, id)
  display_result(ctx.device, d)
end

up(ctx::Context, c::Change) = begin
  p = path(ctx)
  isnothing(p) ? c : Assoc(p, c)
end
up(ctx::Context, c::Delete) = Dissoc(path(ctx))
up(ctx::Context) = ctx.parent

current_device(ctx=context[]) = top(ctx).device
current_device(::Nothing) = nothing
top(ctx::TopLevelContext) = ctx
top(ctx::Context) = top(ctx.parent)

@use "./draw.jl" draw doodle
@use "./stdlib/TextField.jl" TextField
@use "./stdlib/Stack.jl" VStack StackItem
