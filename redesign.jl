@use "github.com" [
  "jkroso" [
    "DOM.jl" => DOM @dom @css_str ["Events.jl" => Events]
    "Prospects.jl" @mutable @abstract @struct Field assoc
    "Promises.jl" need pending]
  "JunoLab/Atom.jl" => Atom]
@use "./draw.jl" doodle vstack hstack chevron brief

const json = MIME("application/json")

msg(x; kwargs...) = msg(x, kwargs)
# TODO: figure out why I need to buffer the JSON in a String before writing it
msg(x::String, args...) = Atom.isactive(Atom.sock) && println(Atom.sock, repr(json, Any[x, args...]))

const evallock = ReentrantLock()
const empty_attrs = Base.ImmutableDict{Symbol,Any}()

@abstract struct Event end
@abstract struct UINode
  attrs::AbstractDict{Symbol,Any}=empty_attrs
  parent::Union{Nothing, UINode}=nothing
  previous_sibling::Union{Nothing, UINode}=nothing
  next_sibling::Union{Nothing, UINode}=nothing
  first_child::Union{Nothing, UINode}=nothing
end

@struct Snippet(text::String, line::Int32, path::String, id::Int32)

evaluate(s::Snippet) =
  lock(evallock) do
    Atom.withpath(s.path) do
      m = Kip.get_module(s.path, interactive=true)
      res = Atom.@errs include_string(m, s.text, s.path, s.line)
      res isa Atom.EvalError && showerror(IOContext(stderr, :limit => true), res)
      res
    end
  end

mutable struct InlineResult
  snippet::Snippet
  error::Bool
  data::Any
  ui::UINode
  view::DOM.Node
  InlineResult(snippet) = begin
    data = evaluate(snippet)
    ui = createUI(data)
    d = new(snippet, data isa Atom.EvalError, data, ui)
    # d.ui = DocumentNode(ui, d)
    # ui.parent = d.ui
    d
  end
end

@mutable DocumentNode(ui::UINode, device::InlineResult) <: UINode
Base.convert(::Type{DOM.Node}, d::DocumentNode) = convert(DOM.Node, d.ui)

"used to tell emit() to stop recursion"
const stop = Ref{Bool}(false)

emit(d::InlineResult, e) = begin
  stop[] = false
  emit(d, e, 1)
end
emit(d::InlineResult, e, i) = begin
  if haskey(cache, d.ui)
    emit(cache[d.ui], e, i)
  end
end
emit(d::DOM.Container, e, i) = begin
  path = Events.path(e)
  if length(path) >= i
    child = d.children[path[i]]
    emit(child, e, i + 1)
  end
  stop[] && return nothing
  fn = get(d.attrs, Events.name(e), nothing)
  isnothing(fn) || fn(e)
  nothing
end

Base.display(d::InlineResult, view::DOM.Node) = begin
  state = d.error ? :error : :ok
  # update CSS if its stale
  if DOM.css[].state == pending
    msg("stylechange", need(DOM.css[]))
  end
  if isdefined(d, :view)
    patch = DOM.diff(d.view, view)
    isnothing(patch) || msg("patch", (id=d.snippet.id, patch=patch, state=state))
  else
    msg("render", (state=state, id=d.snippet.id, dom=view))
  end
  d.view = view
end

macro ui(expr) handle_expr(expr) end
handle_expr(x::Any) = esc(x)
handle_expr(expr::Expr) = begin
  if expr.head in (:hcat, :vcat, :array, :vect)
    this = tocall(expr.args[1])
    children = map(handle_expr, expr.args[2:end])
    :(tree($this, $(children...)))
  else
    esc(expr)
  end
end

tocall(s::Symbol) = Expr(:call, esc(s), empty_attrs, nothing, nothing, nothing, nothing)
tocall(s::Expr) = begin
  @assert Meta.isexpr(s, :call)
  args = s.args[2:end]
  Expr(:call, esc(s.args[1]), map(esc, args)..., empty_attrs, nothing, nothing, nothing, nothing)
end

tree(node, children...) = begin
  prev_sibling = nothing
  for child in children
    child.parent = node
    if isnothing(prev_sibling)
      node.first_child = child
    else
      prev_sibling.next_sibling = child
      child.previous_sibling = prev_sibling
    end
    prev_sibling = child
  end
  node
end

@struct ChildNodes(sibling::Union{UINode,Nothing}, len::Integer=siblings(sibling))
siblings(::Nothing) = 0
siblings(ui::UINode) = 1 + siblings(ui.next_sibling)
Base.getproperty(ui::UINode, f::Symbol) = getproperty(ui, Field{f}())
Base.getproperty(ui::UINode, f::Field{:children}) = ChildNodes(ui.first_child)
Base.iterate(c::ChildNodes) = iterate(c, (c.sibling, c.len))
Base.iterate(c::ChildNodes, (node, len)) = len < 1 ? nothing : (node, (node.next_sibling, len-1))
Base.eltype(c::ChildNodes) = UINode
Base.length(c::ChildNodes) = c.len
Base.getindex(c::ChildNodes, r::UnitRange) = ChildNodes(c[r.start], r.stop - (r.start-1))
Base.getindex(c::ChildNodes, i::Integer) = begin
  0 < i <= length(c) || throw(BoundsError())
  node = c.sibling
  while i > 1
    node = node.next_sibling
    i -= 1
  end
  node
end

const cache = IdDict{UINode,DOM.Node}()
uncache(x::UINode) = delete!(cache, x)

Base.convert(::Type{DOM.Node}, ui::UINode) = begin
  dom = toDOM(ui)
  dom = assoc(dom, :attrs, assoc(dom.attrs, :id, string(objectid(ui), base=62)))
  finalizer(uncache, ui)
  cache[ui] = dom
end

redraw(ui::UINode) = begin
  old = cache[ui]
  id = string(objectid(ui), base=62)
  new = toDOM(ui)
  new = assoc(new, :attrs, assoc(new.attrs, :id, id))
  cache[ui] = new
  patch = DOM.diff(old, new)
  isnothing(patch) || msg("patchnode", (node=id, patch=patch))
  nothing
end

@mutable StaticView(data) <: UINode
toDOM(ui::StaticView) = doodle(ui.data)

@mutable DictUI(dict::AbstractDict, isopen=false) <: UINode
toDOM(ui::DictUI) = begin
  isopen = ui.isopen
  onmousedown(_) = begin
    ui.isopen = !isopen
    redraw(ui)
  end
  @dom[vstack
    [hstack{onmousedown} css"align-items: center" chevron(isopen) brief(ui.dict)]
    [vstack class.isopen=isopen
            css"&.isopen {height: auto}"
            css"padding: 0 0 3px 20px; overflow: auto; max-height: 500px; height: 0px"
      ui.children...]]
end

@mutable DictEntry(kv::Pair) <: UINode
toDOM(ui::DictEntry) = begin
  key, value = ui.children
  @dom[hstack key " → " value]
end

"""
Takes some data and generates a user interface for viewing and manipulating it
"""
createUI(data) = StaticView(data)
createUI(dict::AbstractDict) = begin
  @ui[DictUI(dict, false)
    (@ui[DictEntry(kv) createUI(kv[1]) createUI(kv[2])] for kv in dict)...]
end

"""
Tells the UINode that time has passed. If components need to mutate themselves as
time passes they can specialize this function
"""
tick(ui::UINode) = foreach(tick, ui.children)

"""
This is invoked when the user interacts with the `UINode`. Usually either a
mouse event or a keystroke
"""
emit(ui::UINode, e::Event) = begin
  for child in ui.children
    emit(child, e) && return true
  end
  onevent(ui, e)
end

onevent(ui::UINode, e::Event) = false
