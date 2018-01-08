@require ".." => Rutherford UI render @component
@require "github.com/jkroso/DOM.jl" => DOM @dom @css_str
@require "github.com/jkroso/Destructure.jl" @destruct
@require "github.com/jkroso/write-json.jl"
@require "github.com/jkroso/parse-json.jl"
import CodeTools
import Atom
import Juno

# TODO: figure out why I need to buffer the JSON in a String before writing it
msg(args...) = Atom.isactive(Atom.sock) && println(Atom.sock, stringmime("application/json", Any[args...]))

Atom.handle("get-stylesheets") do
  parse(MIME("application/json"), sprint(show, MIME("application/json"), DOM.stylesheets))
end

const UIs = Dict{Int32,Any}()

event_parsers = Dict{String,Function}(
  "mousedown" => d-> DOM.Events.MouseDown(d["path"], d["button"], d["position"]...),
  "mouseup" => d-> DOM.Events.MouseUp(d["path"], d["button"], d["position"]...),
  "keydown" => d-> DOM.Events.KeyDown(d["path"], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))),
  "keyup" => d-> DOM.Events.KeyUp(d["path"], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))))

Atom.handle("event") do id, data
  ui = UIs[id]
  e = event_parsers[data["type"]](data)
  DOM.emit(ui, e)
end

Atom.handle("reset-module") do file
  delete!(Kip.modules, file)
  getmodule(file)
  nothing
end

mutable struct Editor
  id::Int
  iserror::Bool
  view::Any
  Editor(id, bool) = new(id, bool)
end

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

Atom.handle("myeval") do data
  @destruct {"text"=>text, "line"=>line, "path"=>path, "id"=>id} = data

  lock(Atom.evallock)
  result = Atom.withpath(path) do
    Atom.@errs include_string(getmodule(path), text, path, line)
  end
  unlock(Atom.evallock)

  if !Atom.ends_with_semicolon(text) || result isa Atom.EvalError
    Base.invokelatest() do
      device = Editor(id, result isa Atom.EvalError)
      ui = gui(device, result)
      UIs[id] = ui
      Rutherford.couple(device, ui)
    end
  else
    msg("render", Dict(:type=>"result", :id=>id, :dom=>icon("check")))
  end
end

lastsheet = DOM.stylesheets[1]

Base.display(d::Editor, view::DOM.Node) = begin
  # update CSS if its stale
  if DOM.stylesheets[1] != lastsheet
    global lastsheet = DOM.stylesheets[1]
    msg("stylechange", lastsheet)
  end
  if isdefined(d, :view)
    patch = DOM.diff(d.view, view)
    isnull(patch) || msg("patch", Dict(:id => d.id, :patch => patch))
  else
    msg("render", Dict(:type => d.iserror ? "error" : "result",
                       :id => d.id,
                       :dom => view))
  end
  d.view = view
end

Rutherford.couple(i::Editor, ui::UI) = begin
  push!(ui.devices, i)
  display(i, ui)
end

Base.display(d::Editor, ui::UI) = begin
  ui.view = render(ui)
  display(d, ui.view)
end

Atom.handle("result-done") do id
  delete!(UIs, id)
end

gui(device, result) = UI(result->render(device, result), result)
gui(device, result::UI) = result
gui(device, result::DOM.Node) = UI(identity, result)

render(device, value) = render(value)
render(x::Number) = @dom [:span class="syntax--constant syntax--numeric" repr(x)]
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
  Pkg.dir(string(m))
end

render(f::Function) =
  Expandable(name(f)) do
    @dom [:div css"""
          padding: 8px 0
          max-width: 800px
          white-space: normal
          h1 {font-size: 1.4em}
          pre {padding: 0}
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

@component Expandable
Rutherford.default_data(::Expandable) = false
render(self::Expandable, fn, header) = begin
  open = self.ephemeral
  @dom [:div
    [:div onmousedown=e->Rutherford.set_state(self, !open)
      chevron(open)
      header]
    if open
      @dom [:div css"padding: 3px 0 3px 20px" vcat(fn())...]
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
renderMD(l::Markdown.LaTeX) = @dom [:latex class="latex block" block=true Juno.latex2katex(l.formula)]
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
  @dom [:latex class="latex inline" block=false Juno.latex2katex(md.formula)]

render(e::Atom.EvalError) = begin
  strong(e) = @dom [:strong class="error-description" e]
  header = split(Juno.errmsg(e.err), '\n', keep=false)
  trace = Atom.cliptrace(Atom.errtrace(e))
  head = strong(header[1])
  tail = strong(join(header[2:end], '\n'))
  if isempty(trace)
    length(header) == 1 ? head : Expandable((()->tail), head)
  else
    Expandable(head) do
      [length(header) == 1 ? nothing : tail,
       render(trace)]
    end
  end
end

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
  ms = Juno.methodarray(m)
  isempty(ms) && return @dom [:span name(m) " has no methods"]
  length(ms) == 1 && return render(ms[1])
  Expandable(@dom [:span name(m) " has $(length(ms)) methods"]) do
    [@dom([:div render(method)]) for method in ms]
  end
end
