@require ".." couple decouple UI msg render
@require "github.com/jkroso/DOM.jl" => DOM Events @dom @css_str
@require "github.com/JunoLab/CodeTools.jl" => CodeTools
@require "github.com/jkroso/Destructure.jl" @destruct
@require "github.com/jkroso/DynamicVar.jl" @dynamic!
@require "github.com/jkroso/Prospects.jl" assoc
@require "github.com/JunoLab/Atom.jl" => Atom
@require "github.com/jkroso/write-json.jl"
@require "../State" UIState cursor need private FieldTypeCursor
@require "./markdown.jl" renderMD
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
  DOM.emit(UIs[id], event_parsers[data["type"]](data))
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

abstract type Device end

mutable struct DockResult <: Device
  snippet::Snippet
  state::Symbol
  ui::Union{UI,Nothing}
  view::DOM.Node
  DockResult(s) = new(s, :ok)
end

mutable struct InlineResult <: Device
  snippet::Snippet
  state::Symbol
  ui::Union{UI,Nothing}
  view::DOM.Node
  InlineResult(s) = new(s, :ok)
end

msg(::Device, data) = msg(data[:command], data)

"Get the Module associated with the current file"
getmodule(path) =
  get!(Kip.modules, path) do
    @eval Main module $(Symbol(:⭒, Kip.pkgname(path)))
      using InteractiveUtils
      using Kip
    end
  end

global dock_result
const inline_results = Dict{Int32,InlineResult}()
const UIs = Dict{Int32,UI}()

evaluate(s::Snippet) =
  lock(Atom.evallock) do
    Atom.withpath(s.path) do
      Atom.@errs include_string(getmodule(s.path), s.text, s.path, s.line)
    end
  end

init_gui(d::Device, result) = begin
  @destruct {text,id} = d.snippet
  d.state = result isa Atom.EvalError ? :error : :ok
  # if it ends in a semicolon then the user doesn't want to see the result
  if Atom.ends_with_semicolon(text) && state == :ok
    result = icon("check")
  end
  UIs[id] = gui(d, result)
  Base.invokelatest(couple, d, UIs[id])
end

Atom.handle("rutherford eval") do data
  @destruct {"text"=>text, "line"=>line, "path"=>path, "id"=>id} = data
  snippet = Snippet(text, line, path, id)
  result = evaluate(snippet)
  others = [(r, evaluate(r.snippet)) for r in values(inline_results) if r.snippet.line != line]
  device = if result isa UI
    global dock_result = DockResult(snippet)
  else
    @isdefined(dock_result) && Base.invokelatest(display, dock_result)
    inline_results[id] = InlineResult(snippet)
  end
  Base.invokelatest(init_gui, device, result)
  # redraw all other snippets
  for (device, result) in others
    Base.invokelatest(init_gui, device, result)
  end
end

Base.display(d::DockResult) = begin
  d.ui.view = render(d.ui)
  display(d, d.ui.view)
end

lastsheet = DOM.CSSNode()

Base.display(d::Device, view::DOM.Node) = begin
  # update CSS if its stale
  if DOM.stylesheets[1] != lastsheet
    global lastsheet = DOM.stylesheets[1]
    msg("stylechange", lastsheet)
  end
  if isdefined(d, :view)
    patch = DOM.diff(d.view, view)
    patch == nothing || msg("patch", (id=d.snippet.id, patch=patch, state=d.state))
  else
    msg("render", (state=d.state, id=d.snippet.id, dom=view, location=location(d)))
  end
  d.view = view
end

location(::InlineResult) = "inline"
location(::DockResult) = "dock"

couple(device::Device, ui::UI) = begin
  push!(ui.devices, device)
  device.ui = ui
  display(device, ui)
end

decouple(i::Device, ui::UI) = begin
  deleteat!(ui.devices, findfirst((x->x === i), ui.devices))
  i.ui = nothing
end

Base.display(d::Device, ui::UI) = begin
  ui.view = render(ui)
  display(d, ui.view)
end

Atom.handle("result done") do id
  delete!(inline_results, id)
  delete!(UIs, id)
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

syntax(x) = @dom[:span class=syntax_class(x) repr(x)]
syntax_class(n::Bool) = ["syntax--constant", "syntax--boolean"]
syntax_class(x::Number) = ["syntax--constant", "syntax--numeric"]
syntax_class(::AbstractString) = ["syntax--string", "syntax--quoted", "syntax--double"]
syntax_class(::Regex) = ["syntax--string", "syntax--regexp"]
syntax_class(::Symbol) = ["syntax--constant", "syntax--other", "syntax--symbol"]
syntax_class(::Char) = ["syntax--string", "syntax--quoted", "syntax--single"]
syntax_class(::VersionNumber) = ["syntax--string", "syntax--quoted", "syntax--other"]
syntax_class(::Nothing) = ["syntax--constant"]
syntax_class(::Function) = ["syntax--support", "syntax--function"]

render(n::Union{AbstractFloat,Integer}) = @dom[:span class=syntax_class(n) seperate(n)]
render(x::Union{AbstractString,Regex,Symbol,Char,VersionNumber,Nothing,Number}) = syntax(x)
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

render(m::Module) = begin
  file = getfile(m)
  readme = joinpath(dirname(file), "Readme.md")
  expandable(@dom[:span brief(m) " from " stacklink(file, 0)]) do
    @dom[:div css"max-height: 500px; max-width: 1000px"
      if isfile(readme)
        expandable(@dom[:h3 "Readme.md"], private(readme, false)) do
          renderMDFile(readme)
        end
      end
      (@dom[:div css"display: flex"
        [:span String(name)]
        [:span css"padding: 0 10px" "→"]
        isdefined(m, name) ? render(cursor[][name]) : fade("#undef")]
      for name in names(m, all=true) if !occursin('#', String(name)) && name != nameof(m))...]
  end
end

renderMDFile(path) = resolveImages(render(Markdown.parse_file(path)), dirname(path))

resolveImages(c::DOM.Node, dir) = c
resolveImages(c::DOM.Container, dir) = assoc(c, :children, map(c->resolveImages(c, dir), c.children))
resolveImages(c::DOM.Container{:img}, dir) = begin
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
brief(data) =
  @dom[:span brief(typeof(data)) [:span css"color: rgb(104, 110, 122)" "[$(length(data))]"]]

"By default just render the structure of the object"
render(data::T) where T = begin
  attrs = fields(T)
  isempty(attrs) && return brief(T)
  expandable(brief(T)) do
    @dom[:div
      (@dom[:div css"display: flex"
        [:span String(field)]
        [:span css"padding: 0 10px" "→"]
        render(cursor[][field])]
       for field in attrs)...]
  end
end

brief(T::DataType) = @dom[:span class="syntax--support syntax--type" repr(T)]
header(T::DataType) = begin
  if supertype(T) ≠ Any
    @dom[:span brief(T) " <: " brief(supertype(T))]
  else
    brief(T)
  end
end

render(x::UnionAll) = render(x.body)

render(T::DataType) = begin
  attrs = fields(T)
  isempty(attrs) && return header(T)
  expandable(header(T)) do
    @dom[:div
      (@dom[:div css"display: flex"
        [:span String(name)]
        [:span "::"]
        render(FieldTypeCursor(fieldtype(T, name), cursor[]))]
      for name in attrs)...
      expandable(@dom[:h4 "Methods"], private(methods, false)) do
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

render(m::Method) = begin
  tv, decls, file, line = Base.arg_decl_parts(m)
  params = [@dom[:span x isempty(T) ? "" : "::" [:span class="syntax--support syntax--type" stripparams(T)]]
            for (x, T) in decls[2:end]]
  sig = @dom[:span name(m) "(" interpose(params, ", ")... ")"]
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
  expandable(name(f), private(f, false)) do
    @dom[:div css"""
              padding: 8px 0
              max-width: 800px
              white-space: normal
              h1 {font-size: 1.4em}
              pre {padding: 0}
              > div:last-child > div:last-child {overflow: visible}
              """
      Atom.CodeTools.hasdoc(f) ? render(Base.doc(f)) : @dom[:p "No documentation available"]
      render(methods(f))]
  end

isanon(f) = occursin('#', String(nameof(f)))
name(f::Function) = @dom[:span class=syntax_class(f) isanon(f) ? "λ" : String(nameof(f))]

# Markdown is loose with its types so we need special functions `renderMD`
render(m::Markdown.MD) = @dom[:div class="markdown" map(renderMD, CodeTools.flatten(m).content)...]

render(x::Union{AbstractDict,AbstractVector,Tuple,NamedTuple}) = begin
  isempty(x) && return brief(x)
  expandable(()->body(x), brief(x))
end

render(s::Set) = begin
  isempty(s) && return brief(s)
  expandable(brief(s)) do
    @dom[:div css"> * {display: block}" (render(v) for (i,v) in cursor[])...]
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
  @dom[:div css"> * {display: block}" (render(v) for (k,v) in cursor[])...]

expandable(fn::Function, head, open=private(expandable, false)) = begin
  onmousedown(e) = open[] = !open[]
  @dom[:div
    [:div{onmousedown} css"display: flex; flex-direction: row; align-items: center"
      chevron(open[])
      head]
    if open[]
      @dom[:div css"padding: 3px 0 3px 20px; overflow: auto; max-height: 500px" fn()]
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
