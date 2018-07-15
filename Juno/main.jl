@require ".." => Rutherford UI msg render @component
@require "github.com/jkroso/DOM.jl" => DOM @dom @css_str
@require "github.com/jkroso/Destructure.jl" @destruct
@require "github.com/jkroso/write-json.jl"
import CodeTools
import Atom
import Juno

# TODO: figure out why I need to buffer the JSON in a String before writing it
msg(args...) = Atom.isactive(Atom.sock) && println(Atom.sock, stringmime("application/json", Any[args...]))

const event_parsers = Dict{String,Function}(
  "mousedown" => d-> DOM.Events.MouseDown(d["path"], d["button"], d["position"]...),
  "mouseup" => d-> DOM.Events.MouseUp(d["path"], d["button"], d["position"]...),
  "mouseover" => d-> DOM.Events.MouseOver(d["path"]),
  "mouseout" => d-> DOM.Events.MouseOut(d["path"]),
  "click" => d-> DOM.Events.Click(d["path"], d["button"], d["position"]...),
  "dblclick" => d-> DOM.Events.DoubleClick(d["path"], d["button"], d["position"]...),
  "mousemove" => d-> DOM.Events.MouseMove(d["path"], d["position"]...),
  "keydown" => d-> DOM.Events.KeyDown(d["path"], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))),
  "keyup" => d-> DOM.Events.KeyUp(d["path"], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))),
  "keypress" => d-> DOM.Events.KeyPress(d["path"], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))),
  "resize" => d-> DOM.Events.Resize(d["width"], d["height"]),
  "scroll" => d-> DOM.Events.Scroll(d["path"], d["position"]...))

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
  ui::Union{UI,Void}
  view::DOM.Node
  DockResult(s) = new(s, :ok)
end

mutable struct InlineResult <: Device
  snippet::Snippet
  state::Symbol
  ui::Union{UI,Void}
  view::DOM.Node
  InlineResult(s) = new(s, :ok)
end

msg(::Device, data) = msg(data[:command], data)

"Get the Module associated with the current file"
getmodule(path) =
  get!(Kip.modules, path) do
    name = Kip.pkgname(path)
    mod = Module(Symbol(:⭒, name))
    eval(mod, Expr(:toplevel,
                   :(using Kip),
                   :(eval(x) = Main.Core.eval($mod, x)),
                   :(eval(m, x) = Main.Core.eval(m, x))))
    mod
  end

global dock_result
const inline_results = Dict{Int32,InlineResult}()
const UIs = Dict{Int32,UI}()

evaluate(s::Snippet) = begin
  lock(Atom.evallock)
  result = Atom.withpath(s.path) do
    Atom.@errs include_string(getmodule(s.path), s.text, s.path, s.line)
  end
  unlock(Atom.evallock)
  result
end

display_gui(d::Device, result) = begin
  @destruct {text,id} = d.snippet
  d.state = result isa Atom.EvalError ? :error : :ok
  if Atom.ends_with_semicolon(text) && d.state == :ok
    result = icon("check")
  end
  UIs[id] = gui(d, result)
  Base.invokelatest(Rutherford.couple, d, UIs[id])
end

Atom.handle("rutherford eval") do data
  @destruct {"text"=>text, "line"=>line, "path"=>path, "id"=>id} = data
  snippet = Snippet(text, line, path, id)
  result = evaluate(snippet)
  others = [(r, evaluate(r.snippet)) for r in values(inline_results) if r.snippet.line != line]
  device = if result isa UI
    global dock_result = DockResult(snippet)
  else
    isdefined(:dock_result) && Base.invokelatest(display, dock_result)
    inline_results[id] = InlineResult(snippet)
  end
  Base.invokelatest(display_gui, device, result)
  # redraw all other snippets
  for (device, result) in others
    Base.invokelatest(display_gui, device, result)
  end
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
    isnull(patch) || msg("patch", Dict(:id => d.snippet.id, :patch => patch, :state => d.state))
  else
    msg("render", Dict(:state => d.state, :id => d.snippet.id, :dom => view, :location => location(d)))
  end
  d.view = view
end

location(::InlineResult) = "inline"
location(::DockResult) = "dock"

Rutherford.couple(device::Device, ui::UI) = begin
  push!(ui.devices, device)
  device.ui = ui
  display(device, ui)
end

Rutherford.decouple(i::Device, ui::UI) = begin
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

gui(device, result) = UI(result->render(device, result), result)
gui(device, result::UI) = result
gui(device, result::DOM.Node) = UI(identity, result)

render(device, value) = render(value)
render(x::Number) = @dom [:span class="syntax--constant syntax--numeric" repr(x)]
render(n::Union{AbstractFloat,Integer}) = @dom [:span class="syntax--constant syntax--numeric" seperate(n)]
render(n::Bool) = @dom [:span class="syntax--constant syntax--boolean" string(n)]
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

render(x::AbstractString) = @dom [:span class="syntax--string syntax--quoted syntax--double" repr(x)]
render(x::Symbol) = @dom [:span class="syntax--constant syntax--other syntax--symbol" repr(x)]
render(x::Char) = @dom [:span class="syntax--string syntax--quoted syntax--single" repr(x)]
render(x::VersionNumber) = @dom [:span class="syntax--string syntax--quoted syntax--other" repr(x)]
render(x::Void) = @dom [:span class="syntax--constant" repr(x)]
render(v::Union{Tuple,AbstractVector}) = expandable(v)
render(dict::Associative) = expandable(dict)

body(dict::Associative) =
  [@dom [:div css"display: flex"
    render(key)
    [:span css"padding: 0 10px" "→"]
    render(value)]
  for (key, value) in dict]

body(v::Union{Tuple,AbstractVector}) = [@dom([:div render(x)]) for x in v]

brief(x::Module) = @dom [:span class="syntax--keyword syntax--other" repr(x)]
render(x::Module) = begin
  file = getfile(x)
  Expandable(@dom [:span brief(x) " from " baselink(file, 0)]) do
    @dom [:div css"max-height: 500px"
      (@dom [:div css"display: flex"
        [:span string(name)]
        [:span css"padding: 0 10px" "→"]
        render(getfield(x, name))]
      for name in names(x, true) if !contains(string(name), "#"))...]
  end
end

getfile(m::Module) = begin
  for (file, mod) in Kip.modules
    mod === m && return file
  end
  joinpath(Pkg.dir(string(m)), "src", "$m.jl")
end

render(f::Function) =
  Expandable(name(f)) do
    @dom [:div css"""
               padding: 8px 0
               max-width: 800px
               white-space: normal
               h1 {font-size: 1.4em}
               pre {padding: 0}
               > div:last-child > div:last-child {overflow: visible}
               """
      Atom.CodeTools.hasdoc(f) ? render(Base.doc(f)) : @dom [:p "no docs"]
      render(methods(f))]
  end

isanon(f) = contains(string(f), "#")
name(f::Function) = @dom [:span class="syntax--support syntax--function"
                           isanon(f) ? "λ" : string(typeof(f).name.mt.name)]

"render a chevron symbol that rotates down when open"
chevron(open) =
  @dom [:span class.open=open
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
brief(data) = @dom [:span
                     brief(typeof(data))
                     [:span css"color: rgb(104, 110, 122)" "[$(length(data))]"]]
brief(::Type{T}) where T = @dom [:span class="syntax--support syntax--type" repr(T)]

expandable(data) = begin
  isempty(data) && return brief(data)
  Expandable(()->body(data), brief(data))
end

@component Expandable(open=false)
render(self::Expandable, fn, header) = begin
  @destruct {open} = Rutherford.getstate(self)
  @dom [:div
    [:div onmousedown=e->Rutherford.setstate(self, :open, !open)
      chevron(open)
      header]
    if open
      @dom [:div css"padding: 3px 0 3px 20px; overflow: auto; max-height: 500px" vcat(fn())...]
    end]
end

render(T::DataType) = begin
  head = if supertype(T) ≠ Any
    @dom [:span brief(T) " <: " brief(supertype(T))]
  else
    brief(T)
  end
  fields = fieldnames(T)
  isempty(fields) && return head
  Expandable(head) do
    [@dom [:div css"display: flex"
      [:span string(name)]
      [:span "::"]
      render(fieldtype(T, name))]
    for name in fields]
  end
end

render(x::UnionAll) = render(x.body)

"By default just render the structure of the object"
render(x) = structure(x)

structure(x) =
  Expandable(brief(typeof(x))) do
    [@dom [:div css"display: flex"
      [:span string(field)]
      [:span css"padding: 0 10px" "→"]
      render(getfield(x, field))]
     for field in fieldnames(x)]
  end

# Markdown is loose with its types so we need special functions `renderMD`
render(md::Markdown.MD) =
  @dom [:div class="markdown" map(renderMD, CodeTools.flatten(md).content)...]
renderMD(s::AbstractString) = @dom [:p s]
renderMD(p::Markdown.Paragraph) = @dom [:p map(renderMDinline, vcat(p.content))...]
renderMD(b::Markdown.BlockQuote) = @dom [:blockquote map(renderMD, vcat(p.content))...]
renderMD(l::Markdown.LaTeX) = @dom [:latex class="latex block" block=true Atom.latex2katex(l.formula)]
renderMD(l::Markdown.Link) = @dom [:a href=l.url l.text]
renderMD(md::Markdown.HorizontalRule) = @dom [:hr]

renderMD(h::Markdown.Header{l}) where l =
  DOM.Container{Symbol(:h, l)}(DOM.Attrs(), map(renderMDinline, vcat(h.text)))

renderMD(c::Markdown.Code) =
  @dom [:pre
    [:code class=isempty(c.language) ? "julia" : c.language
           block=true
      c.code]]

renderMD(f::Markdown.Footnote) =
  @dom [:div class="footnote" id="footnote-$(f.id)"
    [:p class="footnote-title" f.id]
    renderMD(f.text)]

renderMD(md::Markdown.Admonition) =
  @dom [:div class="admonition $(md.category)"
    [:p class="admonition-title $(md.category == "warning" ? "icon-alert" : "icon-info")" md.title]
    renderMD(md.content)]

renderMD(md::Markdown.List) =
  DOM.Container{Markdown.isordered(md) ? :ol : :ul}(
    DOM.Attrs(:start=>md.ordered > 1 ? string(md.ordered) : ""),
    [@dom([:li renderMDinline(item)]) for item in md.items])

renderMD(md::Markdown.Table) = begin
  align = map(md.align) do s
    s == :c && return "center"
    s == :r && return "right"
    s == :l && return "left"
  end
  @dom [:table css"""
               border-collapse: collapse
               border-spacing: 0
               empty-cells: show
               border: 1px solid #cbcbcb
               > thead
                 background-color: #e0e0e0
                 color: #000
                 vertical-align: bottom
               > thead > tr > th, > tbody > tr > td
                 font-size: inherit
                 margin: 0
                 overflow: visible
                 padding: 0.5em 1em
                 border-width: 0 0 1px 0
               > tbody > tr:last-child > td
                 border-bottom-width: 0
               """
    [:thead
      [:tr (@dom([:th align=align[i] renderMDinline(column)])
            for (i, column) in enumerate(md.rows[1]))...]]
    [:tbody
      map(md.rows[2:end]) do row
        @dom [:tr (@dom([:td align=align[i] renderMDinline(column)])
                   for (i, column) in enumerate(row))...]
      end...]]
end

renderMDinline(v::Vector) =
  length(v) == 1 ? renderMDinline(v[1]) : @dom [:span map(renderMDinline, v)...]
renderMDinline(md::Union{Symbol,AbstractString}) = DOM.Text(string(md))
renderMDinline(md::Markdown.Bold) = @dom [:b renderMDinline(md.text)]
renderMDinline(md::Markdown.Italic) = @dom [:em renderMDinline(md.text)]
renderMDinline(md::Markdown.Image) = @dom [:img src=md.url alt=md.alt]
renderMDinline(l::Markdown.Link) = @dom [:a href=l.url renderMDinline(l.text)]
renderMDinline(br::Markdown.LineBreak) = @dom [:br]

renderMDinline(f::Markdown.Footnote) =
  @dom [:a href="#footnote-$(f.id)" class="footnote" [:span "[$(f.id)]"]]

renderMDinline(code::Markdown.Code) =
  @dom [:code class=isempty(code.language) ? "julia" : code.language
              block=false
    code.code]

renderMDinline(md::Markdown.LaTeX) =
  @dom [:latex class="latex inline" block=false Atom.latex2katex(md.formula)]

render(e::Atom.EvalError) = begin
  strong(e) = @dom [:strong class="error-description" e]
  header = split(sprint(showerror, e.err), '\n')
  trace = Atom.cliptrace(Atom.errtrace(e))
  head = strong(color(header[1]))
  tail = color(join(header[2:end], '\n'))
  if isempty(trace)
    length(header) == 1 ? head : Expandable((()->tail), head)
  else
    Expandable(head) do
      [length(header) == 1 ? nothing : tail,
       render(trace)]
    end
  end
end

"Handle ANSI color sequences"
color(str) = begin
  matches = eachmatch(r"\e\[(\d{2})m", str)|>collect
  isempty(matches) && return @dom [:span str]
  out = [@dom [:span class=colors[9] str[1:matches[1].offset-1]]]
  for (i, current) in enumerate(matches)
    start = current.offset+length(current.match)
    cutoff = i == endof(matches) ? endof(str) : matches[i+1].offset-1
    class = colors[parse(UInt8, current.captures[1]) - UInt8(30)]
    text = str[start:cutoff]
    push!(out, @dom [:span{class} text])
  end
  @dom [:p out...]
end

const colors = Dict{UInt8,String}([
  0 => css"color: black",
  1 => css"color: red",
  2 => css"color: green",
  3 => css"color: yellow",
  4 => css"color: blue",
  5 => css"color: magenta",
  6 => css"color: cyan",
  7 => css"color: white",
  9 => css"color: lightgray",
  60 => css"color: lightblack",
  61 => css"color: #f96666",
  62 => css"color: lightgreen",
  63 => css"color: lightyellow",
  64 => css"color: lightblue",
  65 => css"color: lightmagenta",
  66 => css"color: lightcyan",
  67 => css"color: lightwhite"])

fade(s) = @dom [:span class="fade" s]
icon(x) = @dom [:span class="icon $("icon-$x")"]

expandpath(path) = begin
  isempty(path) && return (path, path)
  path == "./missing" && return ("<unknown file>", path)
  Atom.isuntitled(path) && return ("untitled", path)
  !isabspath(path) && return (normpath(joinpath("base", path)), Atom.basepath(path))
  ("./" * relpath(path, homedir()), path)
end

baselink(path, line) = begin
  name, path = expandpath(path)
  if name == "<unkown file>"
    fade(name)
  else
    @dom [:a onmousedown=e->(open(path, line); DOM.stop) Atom.appendline(name, line)]
  end
end

open(file, line) = msg("open", Dict(:file=>file, :line=>line-1))

render(trace::StackTrace) = begin
  @dom [:div class="error-trace"
    map(trace) do frame
      line = if isnull(frame.linfo)
        string(frame.func)
      else
        linfo = get(frame.linfo)
        replace(sprint(Base.show_tuple_as_call, linfo.def.name, linfo.specTypes),
                r"\(.*\)$",
                "")
      end
      @dom [:div class="trace-entry $(Atom.locationshading(string(frame.file))[2:end])"
        fade("in ")
        [:span line]
        fade(" at ")
        baselink(string(frame.file), frame.line)
        fade(frame.inlined ? " <inlined>" : "")]
    end...]
end

stripparams(t) = replace(t, r"\{([A-Za-z, ]*?)\}", "")
interpose(xs, y) = map(i -> iseven(i) ? xs[i÷2] : y, 2:2length(xs))

render(m::Method) = begin
  tv, decls, file, line = Base.arg_decl_parts(m)
  params = [@dom [:span x isempty(T) ? "" : "::" [:span class="syntax--support syntax--type" stripparams(T)]]
            for (x, T) in decls[2:end]]
  sig = @dom [:span name(m) "(" interpose(params, ", ")... ")"]
  link = file == :null ? "not found" : baselink(string(file), line)
  @dom [:span sig " at " link]
end

name(m::Base.MethodList) = @dom [:span class="syntax--support syntax--function" string(m.mt.name)]
name(m::Method) = @dom [:span class="syntax--support syntax--function" string(m.name)]

render(m::Base.MethodList) = begin
  ms = Atom.methodarray(m)
  isempty(ms) && return @dom [:span name(m) " has no methods"]
  length(ms) == 1 && return render(ms[1])
  Expandable(@dom [:span name(m) " has $(length(ms)) methods"]) do
    [@dom([:div render(method)]) for method in ms]
  end
end
