@use "github.com/JuliaCollections/OrderedCollections.jl" LittleDict
@use "github.com/jkroso/Prospects.jl" @mutable @abstract @struct Field assoc group interleave
@use "github.com/MikeInnes/MacroTools.jl" => MacroTools @capture @match
@use "github.com/JunoLab/Atom.jl" => Atom
@use "./draw.jl" doodle vstack hstack chevron brief syntax literal stacklink resolveLinks
@use "github.com/JuliaIO/JSON.jl" => JSON
@use "github.com/jkroso/write-json.jl" json
@use "github.com/jkroso/Promises.jl" Promise Deferred need pending @defer
@use "github.com/jkroso/DOM.jl" => DOM @dom @css_str ["Events.jl" => Events]
@use "github.com/jkroso/Units.jl" mm
@use "github.com/jkroso/Units.jl/Typography" pt
using InteractiveUtils
import Markdown

msg(x; kwargs...) = msg(x, kwargs)
msg(x::String, args...) = Atom.isactive(Atom.sock) && println(Atom.sock, json([x, args...]))

const evallock = ReentrantLock()
const eventlock = ReentrantLock()
const empty_attrs = Base.ImmutableDict{Symbol,Any}()

@abstract struct Event end
@abstract struct UINode
  attrs::AbstractDict{Symbol,Any}=empty_attrs
  parent::Union{Nothing, UINode}=nothing
  prevsibling::Union{Nothing, UINode}=nothing
  nextsibling::Union{Nothing, UINode}=nothing
  firstchild::Union{Nothing, UINode}=nothing
end
@mutable HStack <: UINode
toDOM(hs::HStack) = @dom[hstack hs.children...]
@mutable VStack <: UINode
toDOM(vs::VStack) = @dom[vstack vs.children...]
@mutable Text(value) <: UINode
toDOM(t::Text) = @dom[:span t.value]
Base.convert(::Type{UINode}, str::String) = Text(str)
@mutable Heading(level::UInt8) <: UINode
toDOM(ui::Heading) = begin
  h = DOM.Container{Symbol('h', ui.level)}
  @dom[h ui.children...]
end
@mutable Padding(top=0mm, right=0mm, bottom=0mm, left=0mm) <: UINode
toDOM(ui::Padding) = begin
  @dom[:div style.paddingTop=string(convert(pt, ui.top))
            style.paddingRight=string(convert(pt, ui.right))
            style.paddingLeft=string(convert(pt, ui.left))
            style.paddingBottom=string(convert(pt, ui.bottom))
            style.background=get(ui.attrs, :background, "inherit")
            style.borderRadius=string(convert(pt, get(ui.attrs, :borderRadius, 2mm))) ui.children...]
end

@abstract struct LazyNode <: UINode end
Base.getproperty(ui::LazyNode, f::Field{:firstchild}) = begin
  isnothing(getfield(ui, :firstchild)) && tree(ui, children(ui)...)
  getfield(ui, :firstchild)
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
    d = new(snippet, data isa Atom.EvalError, data)
    d.ui = tree(DocumentNode(d), createUI(data))
    d
  end
end

@mutable DocumentNode(device::InlineResult) <: UINode
Base.convert(::Type{DOM.Node}, d::DocumentNode) = convert(DOM.Node, d.firstchild)

"used to tell emit() to stop recursion"
const stop = Ref{Bool}(false)

emit(d::InlineResult, e) = begin
  stop[] = false
  emit(d, e, 1)
end
emit(d::InlineResult, e, i) = begin
  id = str_id(d.ui.firstchild)
  haskey(cache, id) && emit(cache[id], e, i)
end
emit(d::DOM.Container, e, i) = begin
  if haskey(d.attrs, :id)
    d = cache[d.attrs[:id]]
  end
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

macro ui(expr) ui_macro(expr) end
ui_macro(x::Any) = esc(x)
ui_macro(expr::String) = :(Text($expr))
ui_macro(expr::Expr) = begin
  if expr.head in (:hcat, :vcat, :array, :vect)
    args = expr.args
    if Meta.isexpr(args[1], :row)
      args = [args[1].args..., args[2:end]...]
    end
    this = tocall(args[1])
    attrs, children = group(isattr, @view args[2:end])
    children = map(ui_macro, children)
    if !isempty(attrs)
      this.args[end-4] = attr_expression(attrs)
    end
    :(tree($this, $(children...)))
  else
    esc(expr)
  end
end
normalize_attr(e) = begin
  @match e begin
    (a_.b_ = c_) => :($(QuoteNode(a)) => $(QuoteNode(b)) => $(esc(c)))
    ((:a_|a_) = b_) => :($(QuoteNode(a)) => $(esc(b)))
    (s_Symbol) => :($(QuoteNode(s)) => $(esc(s)))
    _ => esc(e)
  end
end
Attrs(attrs::Pair...) = reduce(add_attr!, attrs, init=LittleDict{Symbol,Any}())

tocall(s::Symbol) = Expr(:call, esc(s), empty_attrs, nothing, nothing, nothing, nothing)
tocall(s::Expr) = begin
  @assert Meta.isexpr(s, :call) repr(s)
  args = s.args[2:end]
  Expr(:call, esc(s.args[1]), map(esc, args)..., empty_attrs, nothing, nothing, nothing, nothing)
end
isattr(e) = @capture(e, (_ = _))
normalize_attr(e) =
  @match e begin
    ((:a_|a_) = b_) => :($(QuoteNode(a)) => $(esc(b)))
    (s_Symbol) => :($(QuoteNode(s)) => $(esc(s)))
    _ => esc(e)
  end
add_attr!(d::AbstractDict, (key,value)::Pair{Symbol,<:Pair}) = push!(get!(LittleDict{Symbol,Any}, d, key), value)
add_attr!(d::AbstractDict, (key,value)::Pair) = (d[key] = value; d)
attr_expression(attrs) = :(Attrs($(map(normalize_attr, attrs)...)))

tree(node, children...) = begin
  prev_sibling = nothing
  for child in children
    isnothing(child) && continue
    child = convert(UINode, child)
    child.parent = node
    if isnothing(prev_sibling)
      node.firstchild = child
    else
      prev_sibling.nextsibling = child
      child.prevsibling = prev_sibling
    end
    prev_sibling = child
  end
  node
end

@struct ChildNodes(sibling::Union{UINode,Nothing}, len::Integer=siblings(sibling))
siblings(::Nothing) = 0
siblings(ui::UINode) = 1 + siblings(ui.nextsibling)
Base.getproperty(ui::UINode, f::Symbol) = getproperty(ui, Field{f}())
Base.getproperty(ui::UINode, f::Field{:children}) = ChildNodes(ui.firstchild)
Base.iterate(c::ChildNodes) = iterate(c, (c.sibling, c.len))
Base.iterate(c::ChildNodes, (node, len)) = len < 1 ? nothing : (node, (node.nextsibling, len-1))
Base.eltype(c::ChildNodes) = UINode
Base.length(c::ChildNodes) = c.len
Base.lastindex(c::ChildNodes) = c.len
Base.getindex(c::ChildNodes, r::UnitRange) = ChildNodes(c[r.start], r.stop - (r.start-1))
Base.getindex(c::ChildNodes, i::Integer) = begin
  0 < i <= length(c) || throw(BoundsError())
  node = c.sibling
  while i > 1
    node = node.nextsibling
    i -= 1
  end
  node
end

str_id(x) = string(objectid(x), base=62)
const cache = Dict{String,DOM.Node}()
uncache(x::UINode) = delete!(cache, str_id(x))

Base.convert(::Type{DOM.Node}, ui::UINode) = begin
  dom = toDOM(ui)
  id = str_id(ui)
  if !haskey(dom.attrs, :id)
    dom = assoc(dom, :attrs, assoc(dom.attrs, :id, id))
    finalizer(uncache, ui)
    cache[id] = dom
  end
  dom
end

redraw(ui::UINode) = begin
  id = str_id(ui)
  old = cache[id]
  new = convert(DOM.Node, ui)
  patch = DOM.diff(old, new)
  if !isnothing(patch)
    msg("patchnode", (node=id, patch=patch))
  end
end

"""
Tells the UINode that time has passed. If components need to mutate themselves as
time passes they can specialize this function
"""
tick(ui::UINode) = foreach(tick, ui.children)

"""
Takes some data and generates a user interface for viewing and manipulating it
"""
createUI(data) = isbits(data) ? StaticView(data) : Expandable(data)

@mutable StaticView(data) <: UINode
toDOM(ui::StaticView) = doodle(ui.data)
@mutable BriefView(data) <: UINode
toDOM(ui::BriefView) = brief(ui.data)
@mutable SyntaxView(expr) <: UINode
toDOM(ui::SyntaxView) = syntax(ui.expr)

@abstract struct AbstractExpandable <: LazyNode
  isopen::Bool=false
end
children(ui::AbstractExpandable) = (header(ui), convert(UINode, @defer body(ui)))
toDOM(ui::AbstractExpandable) = begin
  isopen = ui.isopen
  onmousedown(_) = begin
    ui.isopen = !isopen
    redraw(ui)
  end
  @dom[vstack
    [hstack{onmousedown} hi=true css"align-items: center" chevron(isopen) ui.firstchild]
    [vstack style.height=isopen ? "auto" : "0px"
            css"padding: 0 0 3px 20px; overflow: auto; max-height: 500px" isopen ? ui.children[2] : nothing]]
end

@mutable DeferredNode(promise::Promise) <: UINode
Base.convert(::Type{UINode}, p::Promise) = DeferredNode(p)
toDOM(ui::DeferredNode) = convert(DOM.Node, ui.firstchild)
Base.getproperty(ui::DeferredNode, f::Field{:firstchild}) = begin
  if ui.promise.state == pending
    tree(ui, need(ui.promise))
  end
  getfield(ui, :firstchild)
end

@mutable Expando(fn, header) <: AbstractExpandable
header(ui::Expando) = ui.header
body(ui::Expando) = ui.fn()

@mutable Expandable(data::Any) <: AbstractExpandable
header(ui::Expandable) = header(ui.data)
header(data) = BriefView(data)
body(ui::Expandable) = body(ui.data)
body(data::T) where T = begin
  @ui[VStack
    (@ui[HStack
      string(field)
      [Padding(0mm, 2mm, 0mm, 2mm) "→"]
      hasproperty(data, field) ? createUI(getproperty(data, field)) : "#undef"]
    for field in propertynames(data))...]
end

createUI(dict::AbstractDict) = isempty(dict) ? BriefView(dict) : @ui[Expandable(dict, false)]
body(dict::AbstractDict) = @ui[VStack (createUI(kv) for kv in dict)...]

createUI(tuple::NamedTuple) = begin
  @ui[NamedTupleView(tuple, false)
    (@ui[NamedTupleEntry(kv) string(kv[1]) createUI(kv[2])]
     for kv in pairs(tuple))...]
end
@mutable NamedTupleView(nt, isopen=false) <: UINode
toDOM(ui::NamedTupleView) = begin
  isopen = ui.isopen
  onmousedown(_) = begin
    ui.isopen = !isopen
    redraw(ui)
  end
  content = collect(interleave(ui.children, @dom[:span css"padding: 0 6px 0 0" ',']))
  if length(ui.nt) < 6
    length(ui.nt) <= 1 && push!(content, @dom[:span ','])
    return @dom[hstack '(' content... ')']
  end
  header, body = if isopen
    (@dom[hstack '(' ui.children[1] ','],
     [map(c->@dom[hstack c ','], ui.children[2:end-1])..., @dom[hstack ui.children[end] ")"]])
  else
    @dom[hstack '(' content[1:11]... ",...)"], []
  end
  @dom[vstack
    [hstack{onmousedown} css"align-items: center" chevron(isopen) header]
    [vstack class.isopen=isopen
            css"&.isopen {height: auto}"
            css"padding: 0 0 3px 29px; overflow: auto; max-height: 500px; height: 0px" body...]]
end
@mutable NamedTupleEntry(kv::Pair) <: UINode
toDOM(ui::NamedTupleEntry) = begin
  key, value = ui.children
  @dom[hstack key "=" value]
end

createUI(fn::Function) = Expandable(fn, false)
body(fn::Function) = @ui[VStack DocumentationView(fn) Expandable(methods(fn), false)]
@mutable DocumentationView(obj) <: UINode
toDOM(ui::DocumentationView) = Atom.CodeTools.hasdoc(ui.obj) ? doodle(Base.doc(ui.obj)) : @dom[:span]
body(ml::Base.MethodList) = @ui[VStack (@ui[StaticView(m)] for m in ml)...]

@mutable Link(file::Union{String,Nothing}, line::Int) <: UINode
toDOM(ui::Link) = stacklink(ui.file, ui.line)

createUI(m::Module) = Expandable(m, false)
header(m::Module) = @ui[HStack BriefView(m) " from " Link(getfile(m), 0)]
body(m::Module) = begin
  readme = getfile(m)
  @ui[VStack
    isnothing(readme) ? nothing : Expando(()->MDFile(getreadme(readme)), @ui[Heading(4) "Readme.md"])
    (@ui[ModuleField(m, name) SyntaxView(name) createUI(getfield(m, name))]
     for name in names(m, all=true) if !occursin('#', String(name)) && name != nameof(m))...]
end
@mutable ModuleField(mod, name) <: UINode
toDOM(ui::ModuleField) = begin
  name, value = ui.children
  @dom[hstack name [:span css"padding: 0 10px" "→"] value]
end
issubmodule(m::Module) = parentmodule(m) != m && parentmodule(m) != Main
getfile(m::Module) = begin
  if pathof(m) != nothing
    return pathof(m)
  end
  for (file, mod) in Kip.modules
    mod === m && return file
  end
end
getreadme(m::Module) = getreadme(getfile(m))
getreadme(::Nothing) = nothing
getreadme(file::AbstractString) = begin
  dir = dirname(file)
  path = joinpath(dir, "Readme.md")
  isfile(path) && return path
  basename(dir) == "src" || return nothing
  path = joinpath(dirname(dir), "Readme.md")
  isfile(path) && return path
  nothing
end

@mutable MDFile(path) <: UINode
toDOM(ui::MDFile) = resolveLinks(doodle(Markdown.parse_file(ui.path, flavor=Markdown.github)), dirname(ui.path))

const AnyDataType = Union{DataType,UnionAll}
fields(T) = try fieldnames(T) catch; () end
createUI(T::AnyDataType) = begin
  attrs = fields(T)
  isempty(attrs) ? header(T) : Expandable(T, false)
end
header(T::AnyDataType) = begin
  supertype(T) === Any && return BriefView(T)
  @ui[HStack BriefView(T) " <: " BriefView(supertype(T))]
end
body(T::AnyDataType) = begin
  attrs = fields(T)
  @ui[VStack
    Atom.CodeTools.hasdoc(T) ? DocumentationView(Base.doc(T)) : nothing
    [Padding(2mm, 0mm, 0mm, 0mm)]
    [Padding(2mm, 5mm, 2mm, 5mm) background="white" borderRadius=1.5mm
      [VStack
        (@ui[HStack String(name) "::" BriefView(fieldtype(T, name))] for name in attrs)...]]
    Expando(@ui[Heading(4) "Constructors"]) do
      @ui[VStack (StaticView(m) for m in methods(T))...]
    end
    Expando(@ui[Heading(4) "Instance Methods"]) do
      ms = methodswith(T)
      if isempty(ms)
        @ui[HStack "No methods for this type"]
      else
        @ui[VStack (StaticView(m) for m in ms)...]
      end
    end]
end

createUI(s::AbstractString) = SyntaxView(s)
createUI(s::Symbol) = SyntaxView(s)
createUI(n::Number) = StaticView(n)
createUI(p::Pair) = @ui[HStack createUI(p.first) [Padding(0mm,2mm,0mm,2mm) "=>"] createUI(p.second)]

Dict(:a=>1,:b=>Dict(:c=>3))
(a=1,b=(c=3,),c=3,d=4,e=5,f=6,g=7)
(a=1,b=(c=3,),d=4)
identity
@use "github.com/jkroso/Prospects.jl"
Rational
Int
AnyDataType
HStack()
:a=>1
"a"
1//3
1
@ui[Padding(1mm, 1mm,1mm,1mm) background="white"
                              color="red"
  [VStack]
  "Constructors"]
