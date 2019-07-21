@require ".." couple decouple UI msg render cursor need default_state @component
@require "github.com/MikeInnes/MacroTools.jl" rmlines @capture
@require "github.com/jkroso/DOM.jl" => DOM Events @dom @css_str
@require "github.com/JunoLab/CodeTools.jl" => CodeTools
@require "github.com/jkroso/Destructure.jl" @destruct
@require "github.com/jkroso/DynamicVar.jl" @dynamic!
@require "github.com/jkroso/Prospects.jl" assoc interleave
@require "github.com/JunoLab/Atom.jl" => Atom
@require "github.com/jkroso/write-json.jl"
@require "../Entities" FieldTypeCursor
@require "./markdown" renderMD
using InteractiveUtils
import Markdown
import Dates

# TODO: figure out why I need to buffer the JSON in a String before writing it
msg(x::String, args...) =
  Atom.isactive(Atom.sock) && println(Atom.sock, repr("application/json", Any[x, args...]))

const event_parsers = Dict{String,Function}(
  "mousedown" => d-> Events.MouseDown(d["path"], Events.MouseButton(d["button"]), d["position"]...),
  "mouseup" => d-> Events.MouseUp(d["path"], Events.MouseButton(d["button"]), d["position"]...),
  "mouseover" => d-> Events.MouseOver(d["path"]),
  "mouseout" => d-> Events.MouseOut(d["path"]),
  "click" => d-> Events.Click(d["path"], Events.MouseButton(d["button"]), d["position"]...),
  "dblclick" => d-> Events.DoubleClick(d["path"], Events.MouseButton(d["button"]), d["position"]...),
  "mousemove" => d-> Events.MouseMove(d["path"], d["position"]...),
  "keydown" => d-> Events.KeyDown(d["path"], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))),
  "keyup" => d-> Events.KeyUp(d["path"], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))),
  "keypress" => d-> Events.KeyPress(d["path"], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))),
  "resize" => d-> Events.Resize(d["width"], d["height"]),
  "scroll" => d-> Events.Scroll(d["path"], d["position"]...))

# TODO: Should emit events on the device rather than the UI
Atom.handle("event") do id, data
  ui = inline_displays[id].ui
  event = event_parsers[data["type"]](data)
  DOM.emit(ui, event)
end

Atom.handle("reset module") do file
  delete!(Kip.modules, file)
  getmodule(file)
  nothing
end

struct Snippet
  text::String
  line::Int32
  path::String
  id::Int32
end

mutable struct InlineResult
  snippet::Snippet
  state::Symbol
  ui::Union{UI,Nothing}
  view::DOM.Node
  InlineResult(s) = new(s, :ok)
end

msg(::InlineResult, data) = msg(data[:command], data)

"Get the Module associated with the current file"
getmodule(path) =
  get!(Kip.modules, path) do
    @eval Main module $(Symbol(:⭒, Kip.pkgname(path)))
      using InteractiveUtils
      using Kip
    end
  end

const inline_displays = Dict{Int32,InlineResult}()

evaluate(s::Snippet) =
  lock(Atom.evallock) do
    Atom.withpath(s.path) do
      Atom.@errs include_string(getmodule(s.path), s.text, s.path, s.line)
    end
  end

init_gui(d::InlineResult, result) = begin
  @destruct {text,id} = d.snippet
  d.state = result isa Atom.EvalError ? :error : :ok
  # if it ends in a semicolon then the user doesn't want to see the result
  if Atom.ends_with_semicolon(text) && state == :ok
    result = icon("check")
  end
  Base.invokelatest(couple, d, gui(d, result))
end

Atom.handle("rutherford eval") do data
  @destruct {"text"=>text, "line"=>line, "path"=>path, "id"=>id} = data
  snippet = Snippet(text, line, path, id)
  device = InlineResult(snippet)
  inline_displays[id] = device
  result = evaluate(snippet)
  others = [(r, evaluate(r.snippet)) for r in values(inline_displays) if r.snippet.line != line]
  Base.invokelatest(init_gui, device, result)
  # redraw all other snippets
  for (device, result) in others
    Base.invokelatest(init_gui, device, result)
  end
end

lastsheet = DOM.CSSNode()

Base.display(d::InlineResult, view::DOM.Node) = begin
  # update CSS if its stale
  if DOM.stylesheets[1] != lastsheet
    global lastsheet = DOM.stylesheets[1]
    msg("stylechange", lastsheet)
  end
  if isdefined(d, :view)
    patch = DOM.diff(d.view, view)
    patch == nothing || msg("patch", (id=d.snippet.id, patch=patch, state=d.state))
  else
    msg("render", (state=d.state, id=d.snippet.id, dom=view))
  end
  d.view = view
end

couple(device::InlineResult, ui::UI) = begin
  push!(ui.devices, device)
  device.ui = ui
  display(device, ui)
end

decouple(i::InlineResult, ui::UI) = begin
  deleteat!(ui.devices, findfirst((x->x === i), ui.devices))
  i.ui = nothing
end

Base.display(d::InlineResult, ui::UI) = begin
  ui.view = render(ui)
  display(d, ui.view)
end

Atom.handle("result done") do id
  delete!(inline_displays, id)
end

gui(device, result) = UI(render, result)
gui(device, result::UI) = result
gui(device, result::DOM.Node) = UI(identity, result)

"""
Formats long numbers with commas seperating it into chunks
"""
seperate(value::Number; kwargs...) = seperate(string(convert(Float64, value)), kwargs...)
seperate(value::Integer; kwargs...) = seperate(string(value), kwargs...)
seperate(str::String, sep = ",", k = 3) = begin
  parts = split(str, '.')
  str = parts[1]
  n = length(str)
  groups = (str[max(x-k+1, 1):x] for x in reverse(n:-k:1))
  length(parts) == 1 && return join(groups, sep)
  join([join(groups, sep), parts[2]], '.')
end

syntax(x) = @dom[:span class="syntax--language syntax--julia" class=syntax_class(x) repr(x)]
syntax_class(n::Bool) = ["syntax--constant", "syntax--boolean"]
syntax_class(x::Number) = ["syntax--constant", "syntax--numeric"]
syntax_class(::AbstractString) = ["syntax--string", "syntax--quoted", "syntax--double"]
syntax_class(::Regex) = ["syntax--string", "syntax--regexp"]
syntax_class(::Symbol) = ["syntax--constant", "syntax--other", "syntax--symbol"]
syntax_class(::Char) = ["syntax--string", "syntax--quoted", "syntax--single"]
syntax_class(::VersionNumber) = ["syntax--string", "syntax--quoted", "syntax--other"]
syntax_class(::Nothing) = ["syntax--constant"]
syntax_class(::Function) = ["syntax--support", "syntax--function"]
syntax_class(e::Missing) = []

render(n::Union{AbstractFloat,Integer}) = @dom[:span class="syntax--language syntax--julia syntax--constant syntax--numeric" seperate(n)]
render(x::Union{AbstractString,Regex,Symbol,Char,VersionNumber,Nothing,Number,Missing}) = syntax(x)
render(b::Bool) = syntax(b)
render(d::Dates.Date) = @dom[:span Dates.format(d, Dates.dateformat"dd U Y")]
render(d::Dates.DateTime) = @dom[:span Dates.format(d, Dates.dateformat"dd/mm/Y H\h M\m S.s\s")]

brief(m::Module) = @dom[:span class="syntax--keyword syntax--other" replace(repr(m), r"^Main\."=>"")]

getfile(m::Module) = begin
  if pathof(m) != nothing
    return pathof(m)
  end
  for (file, mod) in Kip.modules
    mod === m && return file
  end
end

issubmodule(m::Module) = parentmodule(m) != m && parentmodule(m) != Main
getreadme(file::AbstractString) = begin
  dir = dirname(file)
  path = joinpath(dir, "Readme.md")
  isfile(path) && return path
  basename(dir) == "src" || return nothing
  path = joinpath(dirname(dir), "Readme.md")
  isfile(path) && return path
  nothing
end

render(m::Module) = begin
  readme = nothing
  header = if issubmodule(m)
    brief(m)
  else
    file = getfile(m)
    readme = getreadme(file)
    @dom[:span brief(m) " from " stacklink(file, 0)]
  end
  expandable(header) do
    @dom[:div css"max-height: 500px; max-width: 1000px"
      if readme != nothing
        expandable(@dom[:h3 "Readme.md"]) do
          @dom[:div css"margin-bottom: 20px" renderMDFile(readme)]
        end
      end
      (@dom[:div css"display: flex"
        [:span String(name)]
        [:span css"padding: 0 10px" "→"]
        isdefined(m, name) ? render(cursor[][name]) : fade("#undef")]
      for name in names(m, all=true) if !occursin('#', String(name)) && name != nameof(m))...]
  end
end

renderMDFile(path) = resolveLinks(render(Markdown.parse_file(path, flavor=Markdown.github)), dirname(path))

resolveLinks(c::DOM.Node, dir) = c
resolveLinks(c::DOM.Container, dir) = assoc(c, :children, map(c->resolveLinks(c, dir), c.children))
resolveLinks(c::DOM.Container{:img}, dir) = begin
  haskey(c.attrs, :src) || return c
  src = joinpath(dir, c.attrs[:src])
  assoc(c, :attrs, assoc(c.attrs, :src, src))
end

"render a chevron symbol that rotates down when open"
chevron(open) =
  @dom[:span class.open=open
             class="icon-chevron-right"
             css"""
             &.open {transform: rotate(0.25turn)}
             text-align: center
             transition: transform 0.1s ease-out
             float: left
             width: 1em
             margin-right: 4px
             """]

"A summary of a datastructure"
brief(data) = render(data)
brief(u::UnionAll) = brief(u.body)
brief(data::Union{AbstractDict,AbstractVector,Set,Tuple,NamedTuple}) =
  @dom[:span brief(typeof(data)) [:span css"color: rgb(104, 110, 122)" "[$(length(data))]"]]

brief(u::Union) = @dom[:span
  [:span class="syntax--support syntax--type" "Union"]
  [:span "{"]
  interleave(map(brief, union_params(u)), ",")...
  [:span "}"]]

union_params(u::Union) = push!(union_params(u.b), u.a)
union_params(u) = Any[u]

"By default just render the structure of the object"
render(data::T) where T = begin
  attrs = fields(T)
  isempty(attrs) && return brief(T)
  expandable(brief(T)) do
    @dom[:div
      (@dom[:div css"display: flex"
        [:span String(field)]
        [:span css"padding: 0 10px" "→"]
        isdefined(data, field) ? render(cursor[][field]) : fade("#undef")]
       for field in attrs)...]
  end
end

brief(T::DataType) =
  @dom[:span
    [:span class="syntax--support syntax--type" T.name.name]
    if !isempty(T.parameters)
      @dom[:span css"display: inline-flex; flex-direction: row"
        [:span "{"] interleave(map(brief, T.parameters), ",")... [:span "}"]]
    end]

header(T::DataType) = begin
  if supertype(T) ≠ Any
    @dom[:span brief(T) ' ' kw_subclass ' ' brief(supertype(T))]
  else
    brief(T)
  end
end

brief(t::TypeVar) = @dom[:span repr(t)]
brief(s::Symbol) = render(s)

render(x::UnionAll) = render(x.body)

render(T::DataType) = begin
  attrs = fields(T)
  isempty(attrs) && return header(T)
  expandable(header(T)) do
    @dom[:div
      Atom.CodeTools.hasdoc(T) ? render(Base.doc(T)) : nothing
      [:div css"padding: 3px 5px; background: white; border-radius: 3px; margin: 3px 0"
        (@dom[:div css"display: flex"
          [:span String(name)]
          [:span "::"]
          render(FieldTypeCursor(fieldtype(T, name), cursor[]))]
        for name in attrs)...]
      expandable(@dom[:h4 "Constructors"]) do
        name = @dom[:span class="syntax--support syntax--function" string(T.name.name)]
        @dom[:div css"> * {display: block}"
          (render_method(m, name=name) for m in methods(T))...]
      end
      expandable(@dom[:h4 "Instance Methods"]) do
        @dom[:div css"> * {display: block}"
          (render(m) for m in methodswith(toUnionAll(T), supertypes=true))...]
      end]
  end
end

toUnionAll(T::DataType) = T.name.wrapper
toUnionAll(U::UnionAll) = U

fields(T) = try fieldnames(T) catch; () end

fade(s) = @dom[:span class="fade" s]
icon(x) = @dom[:span class="icon $("icon-$x")"]

expandpath(path) = begin
  isempty(path) && return (path, path)
  Atom.isuntitled(path) && return ("untitled", path)
  !isabspath(path) && return (normpath(joinpath("base", path)), Atom.basepath(path))
  ("./" * relpath(path, homedir()), path)
end

stacklink(::Nothing, line) = fade("<unknown file>")
stacklink(path, line) = begin
  path == "none" && return fade("$path:$line")
  path == "./missing" && return fade("./missing")
  name, path = expandpath(path)
  @dom[:a onmousedown=e->(open(path, line); DOM.stop) Atom.appendline(name, line)]
end

open(file, line) = msg("open", (file=file, line=line-1))

brief(f::StackTraces.StackFrame) = begin
  f.linfo isa Nothing && return @dom[:span string(f.func)]
  f.linfo isa Core.CodeInfo && return @dom[:span repr(f.linfo.code[1])]
  @dom[:span replace(sprint(Base.show_tuple_as_call, f.linfo.def.name, f.linfo.specTypes),
                     r"^([^(]+)\(.*\)$"=>s"\1")]
end

render(trace::StackTraces.StackTrace) = begin
  @dom[:div class="error-trace"
    map(trace) do frame
      @dom[:div class="trace-entry $(Atom.locationshading(string(frame.file))[2:end])"
        fade("in ")
        brief(frame)
        fade(" at ")
        stacklink(String(frame.file), frame.line)
        fade(frame.inlined ? " <inlined>" : "")]
    end...]
end

stripparams(t) = replace(t, r"\{([A-Za-z, ]*?)\}"=>"")
interpose(xs, y) = map(i -> iseven(i) ? xs[i÷2] : y, 2:2length(xs))

render(m::Method) = render_method(m)
render_method(m::Method; name=name(m)) = begin
  tv, decls, file, line = Base.arg_decl_parts(m)
  params = [@dom[:span x isempty(T) ? "" : "::" [:span class="syntax--support syntax--type" stripparams(T)]]
            for (x, T) in decls[2:end]]
  sig = @dom[:span name "(" interpose(params, ", ")... ")"]
  link = file == :null ? "not found" : stacklink(string(file), line)
  @dom[:span sig " at " link]
end

name(m::Base.MethodList) = @dom[:span class="syntax--support syntax--function" string(m.mt.name)]
name(m::Method) = @dom[:span class="syntax--support syntax--function" string(m.name)]

render(m::Base.MethodList) = begin
  ms = Atom.methodarray(m)
  isempty(ms) && return @dom [:span name(m) " has no methods"]
  length(ms) == 1 && return render(ms[1])
  expandable(@dom[:span name(m) " has $(length(ms)) methods"]) do
    @dom[:div (@dom[:div render(method)] for method in ms)...]
  end
end

render(f::Function) =
  expandable(name(f)) do
    @dom[:div css"""
              max-width: 800px
              white-space: normal
              h1 {font-size: 1.4em}
              pre {padding: 0}
              > div:last-child > div:last-child {overflow: visible}
              """
      Atom.CodeTools.hasdoc(f) ? @dom[:div css"padding: 8px 0" render(Base.doc(f))] : nothing
      render(methods(f))]
  end

isanon(f) = occursin('#', String(nameof(f)))
name(f::Function) = @dom[:span class=syntax_class(f) isanon(f) ? "λ" : String(nameof(f))]

# Markdown is loose with its types so we need special functions `renderMD`
render(m::Markdown.MD) = @dom[:div class="markdown" map(renderMD, CodeTools.flatten(m).content)...]

render(x::Union{AbstractDict,AbstractVector}) = begin
  isempty(x) && return brief(x)
  expandable(()->body(x), brief(x))
end

render(t::NamedTuple) = begin
  length(t) < 5 && return literal(t)
  expandable(()->body(t), brief(t))
end

render(t::Tuple) = begin
  length(t) < 10 && return literal(t)
  expandable(()->body(t), brief(t))
end

literal(t::Tuple) = begin
  content = interleave(map(render, cursor[]), @dom[:span css"padding: 0 6px 0 0" ',']) |> collect
  length(content) == 1 && push!(content, @dom[:span ','])
  @dom[:span css"display: flex; flex-direction: row" [:span '('] content... [:span ')']]
end

literal(t::NamedTuple) = begin
  items = (@dom[:span css"display: flex; flex-direction: row" need(k) '=' render(v)] for (k,v) in cursor[])
  content = interleave(items, @dom[:span css"padding: 0 6px 0 0" ',']) |> collect
  length(content) == 1 && push!(content, @dom[:span ','])
  @dom[:span css"display: flex; flex-direction: row" [:span '('] content... [:span ')']]
end

render(s::Set) = begin
  isempty(s) && return brief(s)
  expandable(brief(s)) do
    @dom[:div css"> * {display: block}" (render(v) for v in cursor[])...]
  end
end

brief(nt::NamedTuple) =
  @dom[:span
    [:span class="syntax--support syntax--type" "NamedTuple"]
    [:span css"color: rgb(104, 110, 122)" "[$(length(nt))]"]]

body(nt::NamedTuple) =
  @dom[:div
    (@dom[:div css"display: flex"
      String(need(key))
      [:span css"padding: 0 5px" "="]
      render(value)]
    for (key, value) in cursor[])...]

body(dict::AbstractDict) =
  @dom[:div
    (@dom[:div css"display: flex"
      render(key)
      [:span css"padding: 0 10px" "→"]
      render(value)]
    for (key, value) in cursor[])...]

body(v::Union{Tuple,AbstractVector}) =
  @dom[:div css"> * {display: block}" map(render, cursor[])...]

expandable(fn::Function, head) = @dom[Expandable thunk=fn head]

"Shows a brief view that can be toggled into a more detailed view"
@component Expandable
default_state(::Type{Expandable}) = false
render(e::Expandable) = begin
  isopen = e.state
  @dom[:div
    [:div css"display: flex; flex-direction: row; align-items: center"
          onmousedown=(_)->e.state = !isopen
      chevron(isopen)
      e.children...]
    if isopen
      @dom[:div css"padding: 0 0 3px 20px; overflow: auto; max-height: 500px" e.attrs[:thunk]()]
    end]
end

render(e::Atom.EvalError) = begin
  header = split(sprint(showerror, e.err), '\n')
  trace = Atom.cliptrace(Atom.errtrace(e))
  head = @dom[:strong class="error-description" color(header[1])]
  tail = color(join(header[2:end], '\n'))
  if isempty(trace)
    return length(header) == 1 ? head : expandable((()->tail), head)
  end
  expandable(head) do
    if length(header) == 1
      render(trace)
    else
      @dom[:div tail render(trace)]
    end
  end
end

"Handle ANSI color sequences"
color(str) = begin
  matches = eachmatch(r"\e\[(\d{2})m", str)|>collect
  isempty(matches) && return @dom[:span str]
  out = [@dom[:span style.color="lightgray" str[1:matches[1].offset-1]]]
  for (i, current) in enumerate(matches)
    start = current.offset+length(current.match)
    cutoff = i == endof(matches) ? endof(str) : matches[i+1].offset-1
    color = colors[parse(UInt8, current.captures[1]) - UInt8(30)]
    text = str[start:cutoff]
    push!(out, @dom[:span{style.color=color} text])
  end
  @dom[:p out...]
end

const colors = Dict{UInt8,String}(
  0 => "black",
  1 => "red",
  2 => "green",
  3 => "yellow",
  4 => "blue",
  5 => "magenta",
  6 => "cyan",
  7 => "white",
  9 => "lightgray",
  60 => "lightblack",
  61 => "#f96666",
  62 => "lightgreen",
  63 => "lightyellow",
  64 => "lightblue",
  65 => "lightmagenta",
  66 => "lightcyan",
  67 => "lightwhite")

const context = Ref{Symbol}(:general)

render(e::Expr) = expr(e)

expr(e::Expr) = expr(e, Val(e.head))
expr(e::Any) = @dom[:span css"color: #383a42" bracket('(') render(e) bracket(')')]
expr(r::GlobalRef) = @dom[:span string(r)]
expr(s::Symbol) =
  if context[] == :ref && s == :end
    @dom[:span class="syntax--constant syntax--numeric syntax--julia" "end"]
  elseif s == :nothing
    @dom[:span class="syntax--constant syntax--language syntax--julia" "nothing"]
  else
    @dom[:span class="syntax--language syntax--julia" s]
  end
expr(n::Union{Number,String,Char}) = render(n)
expr(q::QuoteNode) =
  if q.value isa Symbol
    ast = Meta.parse(repr(q.value))
    if ast isa QuoteNode
      @dom[:span class="syntax--constant syntax--other syntax--symbol syntax--julia" repr(q.value)]
    else
      expr(ast)
    end
  else
    @dom[:span ':' bracket('(') render(q.value) bracket(')')]
  end

expr(string, ::Val{:string}) = begin
  @dom[:span class="syntax--string syntax--quoted syntax--double syntax--julia"
    [:span class="syntax--punctuation syntax--definition syntax--string syntax--begin syntax--julia" '"']
    map(render_interp, string.args)...
    [:span class="syntax--punctuation syntax--definition syntax--string syntax--end syntax--julia" '"']]
end

render_interp(x::String) = x
render_interp(x) = @dom[:span class="syntax--variable syntax--interpolation syntax--julia" "\$(" render(x) ')']

expr(q, ::Val{:quote}) = begin
  @dom[:div
    [:span class="syntax--keyword syntax--other syntax--julia" "quote"]
    [:div css"padding-left: 1em; display: flex; flex-direction: column"
      map(expr, rmlines(q).args)...]
    end_block]
end

expr(dolla, ::Val{:$}) = begin
  value = dolla.args[1]
  is_simple = value isa Union{Symbol,Number}
  @dom[:span
    [:span class="syntax--keyword syntax--operator syntax--interpolation syntax--julia" '$']
    if !is_simple bracket('(') end
    expr(value)
    if !is_simple bracket(')') end]
end

const comma = @dom[:span class="syntax--meta syntax--bracket syntax--julia" ',']
const comma_seperator = @dom[:span comma ' ']
const begin_block = @dom[:span class="syntax--keyword syntax--control syntax--julia" "begin"]
const end_block = @dom[:span class="syntax--keyword syntax--control syntax--end syntax--julia" "end"]
const equals = @dom[:span class="syntax--keyword syntax--operator syntax--update syntax--julia" '=']
const coloncolon = @dom[:span class="syntax--keyword syntax--operator syntax--relation syntax--julia" "::"]
const kw_for = @dom[:span class="syntax--keyword syntax--control syntax--julia" "for"]
const and_op = @dom[:span class="syntax--keyword syntax--operator syntax--boolean syntax--julia" "&&"]
const or_op = @dom[:span class="syntax--keyword syntax--operator syntax--boolean syntax--julia" "||"]
const dot_op = @dom[:span class="syntax--keyword syntax--operator syntax--dots syntax--julia" '.']
const kw_if = @dom[:span class="syntax--keyword syntax--control syntax--julia" "if"]
const kw_else = @dom[:span class="syntax--keyword syntax--control syntax--julia" "else"]
const kw_elseif = @dom[:span class="syntax--keyword syntax--control syntax--julia" "elseif"]
const kw_subclass = @dom[:span class="syntax--keyword syntax--operator syntax--relation syntax--julia" "<:"]
const kw_where = @dom[:span class="syntax--keyword syntax--other syntax--julia" "where"]
bracket(c::Char) = @dom[:span class="syntax--meta syntax--bracket syntax--julia" c]
type(e) = @dom[:span class="syntax--support syntax--type syntax--julia" expr(e)]
operator(e) =
  if e == :(:)
    @dom[:span class="syntax--keyword syntax--operator syntax--range syntax--julia" e]
  elseif e in [:+ :- :* :/ :^ ://]
    @dom[:span class="syntax--keyword syntax--operator syntax--arithmetic syntax--julia" e == :* ? :× : e]
  elseif e == :!
    @dom[:span class="syntax--keyword syntax--operator syntax--boolean syntax--julia" e]
  elseif e in [:< :> :>= :<= :(==) :(===)]
    @dom[:span class="syntax--keyword syntax--operator syntax--relation syntax--julia" e]
  elseif e in [:| :&]
    @dom[:span class="syntax--keyword syntax--operator syntax--bitwise syntax--julia" e]
  elseif e in [:>> :<< :<<< :>>>]
    @dom[:span class="syntax--keyword syntax--operator syntax--shift syntax--julia" e]
  else
    @dom[:span class="syntax--keyword syntax--operator syntax--julia" e]
  end

expr(call, ::Val{:call}) = begin
  @capture call name_(args__)
  if name isa Symbol && Base.isoperator(name)
    if length(args) == 1
      @dom[:span operator(name) expr(args[1])]
    elseif name == :* && args[1] isa Real && args[2] isa Symbol
      @dom[:span map(expr, args)...]
    else
      @dom[:span css"> .syntax--arithmetic {padding: 0 0.5em}"
        interleave(map(expr, args), operator(name))...]
    end
  else
    simple_call(call)
  end
end

simple_call(call) = begin
  @capture call name_(args__)
  @dom[:span
    [:span class="syntax--entity syntax--name syntax--function syntax--julia"
           css"> :first-child {display: inline-flex}"
      expr(name)]
    bracket('(')
    interleave(map(expr, args), comma_seperator)...
    bracket(')')]
end

expr(block, ::Val{:block}) = begin
  block = rmlines(block)
  length(block.args) == 1 && return expr(block.args[1])
  @dom[:div css"""
            display: flex
            flex-direction: column
            > *
              padding-left: 1em
              &:first-child {padding: 0}
              &:last-child {padding: 0}
            """
    begin_block
    map(expr, block.args)...
    end_block]
end

expr(eq, ::Val{:(=)}) = begin
  op = context[] == :tuple ? equals : @dom[:span css"padding: 0 0.5em" equals]
  @dom[:span interleave(map(expr, eq.args), op)...]
end

expr(eq, ::Val{:kw}) = @dom[:span interleave(map(expr, eq.args), equals)...]

expr(e, ::Val{:(::)}) = begin
  left, right = e.args
  @dom[:span expr(left) coloncolon type(right)]
end

expr(curly, ::Val{:curly}) = begin
  @capture curly name_{params__}
  content = @dynamic! let context = :curlies
    map(expr, params)
  end
  @dom[:span expr(name) bracket('{') interleave(content, comma)... bracket('}')]
end

expr(fn, ::Val{:function}) = begin
  call, body = fn.args
  @dom[:div
    [:span [:span class="syntax--keyword syntax--other syntax--julia" "function"] ' ' expr(call)]
    [:div css"padding-left: 1em; display: flex; flex-direction: column"
      map(expr, rmlines(body).args)...]
    end_block]
end

expr(c, ::Val{:comprehension}) = comprehension(c.args[1], bracket('['), bracket(']'))
expr(g, ::Val{:generator}) = comprehension(g, bracket('('), bracket(')'))

comprehension(g, open, close) = begin
  body = g.args[1]
  assignments = g.args[2:end]
  @dom[:span open expr(body) ' ' kw_for ' '
    interleave(map(expr, assignments), comma_seperator)...
    close]
end

expr(t, ::Val{:tuple}) = begin
  content = @dynamic! let context = :tuple
    interleave(map(expr, t.args), comma_seperator)
  end
  length(content) == 1 && push!(content, comma)
  @dom[:span bracket('(') content... bracket(')')]
end

expr(v, ::Val{:vect}) = begin
  @dom[:span bracket('[') interleave(map(expr, v.args), comma_seperator)... bracket(']')]
end

expr(v, ::Val{:hcat}) = begin
  @dom[:span bracket('[') interleave(map(expr, v.args), ' ')... bracket(']')]
end

expr(v, ::Val{:vcat}) = begin
  rows = v.args
  lines = (row(e, i==length(rows)) for (i, e) in enumerate(rows))
  @dom[:div css"""
            > div
              padding-left: 0.6em
              &:nth-child(2) {display: inline; padding: 0}
            """ bracket('[') lines...]
end

row(e, islast) = begin
  items = interleave(map(expr, e.args), ' ')
  @dom[:div items... islast ? bracket(']') : @dom ';']
end

expr(r, ::Val{:ref}) = begin
  @capture r ref_[args__]
  vals = @dynamic! let context = :ref
    map(expr, args)
  end
  @dom[:span expr(ref) bracket('[') interleave(vals, comma_seperator)... bracket(']')]
end

const kw_const = @dom[:span class="syntax--keyword syntax--storage syntax--modifier syntax--julia" "const"]

expr(c, ::Val{:const}) = begin
  @dom[:span css"> :last-child {display: inline-flex}" kw_const ' ' expr(c.args[1])]
end

expr(cond, ::Val{:if}) = conditional(cond, kw_if)

conditional(cond, kw) = begin
  pred, branch = cond.args
  if !Meta.isexpr(branch, :block)
    branch = Expr(:block, branch)
  else
    branch = rmlines(branch)
  end
  @dom[:div
    [:span kw ' ' expr(pred)]
    [:div css"padding-left: 1em" map(expr, branch.args)...]
    length(cond.args) == 3 ? altbranch(cond.args[3]) : end_block]
end

altbranch(e) =
  if Meta.isexpr(e, :block)
    elsebranch(e)
  elseif Meta.isexpr(e, :elseif)
    conditional(e, kw_elseif)
  else
    elsebranch(Expr(:block, e))
  end

elsebranch(e) =
  @dom[:div
    kw_else
    [:div css"padding-left: 1em" map(expr, rmlines(e).args)...]
    end_block]

binary(e, op) = @dom[:span interleave(map(expr, e.args), op)...]
expr(and, ::Val{:&&}) = binary(and, @dom[:span ' ' and_op ' '])
expr(or,  ::Val{:||}) = binary(or,  @dom[:span ' ' or_op ' '])

expr(dot, ::Val{:.}) = begin
  left, right = dot.args
  r = if right isa QuoteNode && right.value isa Symbol
    expr(right.value)
  elseif Meta.isexpr(right, :tuple) && length(right.args) == 1
    @dom[:span bracket('(') expr(right.args[1]) bracket(')')]
  else
    expr(right)
  end
  @dom[:span expr(left) dot_op r]
end

expr(meta, ::Val{:meta}) = begin
  @dom[:span "\$(" expr(Expr(:call, :Expr, QuoteNode(:meta), QuoteNode(meta.args[1]))) ')']
end

expr(struc, ::Val{:struct}) = begin
  mutable, name, body = struc.args
  @dom[:div
    [:span
      [:span class="syntax--keyword syntax--other syntax--julia" "$(mutable ? "mutable " : "")struct "]
      expr(name)]
    [:div css"""
          display: flex
          flex-direction: column
          padding-left: 1em
          """
      map(expr, rmlines(body).args)...]
    end_block]
end

expr(params, ::Val{:parameters}) = @dom[:span ';' interleave(map(expr, params.args), ", ")...]

expr(e, ::Val{:<:}) = begin
  padding = context[] == :curlies ? css"> :nth-child(2) {padding: 0 0.15em}" : css"> :nth-child(2) {padding: 0 0.5em}"
  @dom[:span class=padding expr(e.args[1]) kw_subclass expr(e.args[2])]
end

expr(e, ::Val{:where}) = binary(e, @dom[:span ' ' kw_where ' '])

expr(e, ::Val{:break}) = @dom[:span class="syntax--keyword syntax--control syntax--julia" "break"]
expr(e, ::Val{:continue}) = @dom[:span class="syntax--keyword syntax--control syntax--julia" "continue"]
expr(e, ::Val{:while}) = begin
  cond, body = e.args
  @dom[:div
    [:span [:span class="syntax--keyword syntax--control syntax--julia" "while"] ' ' expr(cond)]
    [:div css"padding-left: 1em; display: flex; flex-direction: column"
      map(expr, rmlines(body).args)...]
    end_block]
end

expr(e, ::Val{:for}) = begin
  assignments, body = e.args
  nodes = if Meta.isexpr(assignments, :block)
    map(expr, rmlines(assignments).args)
  else
    [expr(assignments)]
  end
  @dom[:div
    [:span kw_for ' ' interleave(nodes, ", ")...]
    [:div css"padding-left: 1em; display: flex; flex-direction: column"
      map(expr, rmlines(body).args)...]
    end_block]
end
