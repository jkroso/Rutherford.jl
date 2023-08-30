@use "github.com/jkroso" [
  "DOM.jl" => DOM @dom @css_str [
    "ansi.jl" ansi
    "html.jl"]
  "Prospects.jl" assoc interleave
  "Destructure.jl" @destruct
  "Unparse.jl" serialize
  "DynamicVar.jl" @dynamic!]
@use "." @component Context path data stop intent context
@use "./markdown" renderMD
@use CodeTools
@use Atom
@use InteractiveUtils
@use Markdown
@use Dates

function doodle end

"Formats long numbers with commas seperating it into chunks"
seperate(value::Number; kwargs...) = seperate(string(convert(Float64, value)), kwargs...)
seperate(value::Integer; kwargs...) = seperate(string(value), kwargs...)
seperate(str::String, sep = ",", k = 3) = begin
  parts = split(str, '.')
  int = parts[1]
  uint = split(int, '-')[end]
  groups = (uint[max(x-k+1, 1):x] for x in reverse(length(uint):-k:1))
  whole_part = @dom[:span startswith(int, '-') ? "-" : "" interleave(groups, @dom[:span css"color: grey" sep])...]
  length(parts) == 1 && return whole_part
  @dom[:span whole_part @dom[:span css"color: grey" "."] parts[2]]
end

vstack(attrs, children) = @dom[:div{attrs...} css"display: flex; flex-direction: column" children...]
hstack(attrs, children) = @dom[:div{attrs...} css"display: flex; flex-direction: row" children...]
spacer(attrs, children) = begin
  @destruct {width=0,height=0,rest...} = attrs
  @dom[:div{style.width=string(width, "px"), style.height=string(height, "px"), rest...}]
end

syntax(x) = @dom[:span class="syntax--language syntax--julia" class=syntax_class(x) repr(x)]
syntax(x::Symbol) = @dom[:span class="syntax--language syntax--julia" class=syntax_class(x) x]
syntax_class(::Bool) = ["syntax--constant", "syntax--boolean"]
syntax_class(::Number) = ["syntax--constant", "syntax--numeric"]
syntax_class(::AbstractString) = ["syntax--string", "syntax--quoted", "syntax--double"]
syntax_class(::Regex) = ["syntax--string", "syntax--regexp"]
syntax_class(::Symbol) = ["syntax--constant", "syntax--other", "syntax--symbol"]
syntax_class(::Char) = ["syntax--string", "syntax--quoted", "syntax--single"]
syntax_class(::VersionNumber) = ["syntax--string", "syntax--quoted", "syntax--other"]
syntax_class(::Nothing) = ["syntax--constant"]
syntax_class(::Function) = ["syntax--support", "syntax--function"]
syntax_class(::Missing) = []

doodle(n::Union{AbstractFloat,Integer}) = @dom[:span class="syntax--language syntax--julia syntax--constant syntax--numeric" seperate(n)]
doodle(n::Unsigned) = @dom[:span class="syntax--language syntax--julia syntax--constant syntax--numeric" repr(n)]
doodle(x::Union{Regex,Symbol,Char,VersionNumber,Nothing,Number,Missing}) = syntax(x)
doodle(b::Bool) = syntax(b)
doodle(d::Dates.Date) = @dom[:span Dates.format(d, Dates.dateformat"dd U Y")]
doodle(d::Dates.DateTime) = @dom[:span Dates.format(d, Dates.dateformat"dd/mm/Y H\h M\m S.s\s")]
doodle(d::Dates.Time) = @dom[:span Dates.format(d, Dates.dateformat"HH:MM:S.s")]

doodle(s::AbstractString) = begin
  if occursin('\n', s)
    @dom[vstack class="syntax--string syntax--quoted syntax--triple syntax--double syntax--julia"
      [:span "\"\"\""]
      [:span css"white-space: pre" s "\"\"\""]]
  else
    syntax(s)
  end
end

doodle(r::Rational) = begin
  whole, part = divrem(r.num, r.den)
  if whole == 0
    fraction(r)
  else
    @dom[:span css"> :first-child {margin-right: 2px}" doodle(whole) fraction(part//r.den)]
  end
end

fraction(r::Rational) =
  @dom[:span css"""
             display: inline-flex
             flex-direction: column
             line-height: 1em
             vertical-align: middle
             > .syntax--numeric {font-size: 0.8em}
             > :first-child {border-bottom: 1px solid rgb(185,185,185); width: 100%; text-align: center}
             """
    doodle(r.num) doodle(r.den)]

brief(m::Module) = @dom[:span class="syntax--keyword syntax--other" replace(repr(m), r"^Main\."=>"")]

resolveLinks(c::DOM.Node, dir) = c
resolveLinks(c::DOM.Container, dir) = assoc(c, :children, map(c->resolveLinks(c, dir), c.children))
resolveLinks(c::DOM.Container{:img}, dir) = begin
  haskey(c.attrs, :src) || return c
  src = c.attrs[:src]
  path = if occursin(r"^https?://", src) || isabspath(src)
    src
  else
    joinpath(dir, src)
  end
  assoc(c, :attrs, assoc(c.attrs, :src, path))
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
doodle(data::T) where T =
  if showable("text/html", data)
    parse(MIME("text/html"), sprint(show, MIME("text/html"), data))
  else
    attrs = propertynames(data)
    isempty(attrs) ? brief(T) : @dom[vstack brief(T) body(data)]
  end

brief(data::T) where T = @dom[:span brief(T) '[' length(propertynames(data)) ']']
brief(n::Union{Number,Char}) = syntax(n)
brief(e::Enum) = doodle(e)
body(data) =
  @dom[vstack
    (@dom[hstack
      [:span string(field)]
      [:span css"padding: 0 10px" "→"]
      hasproperty(data, field) ? doodle(getproperty(data, field)) : fade("#undef")]
     for field in propertynames(data))...]

brief(x::UnionAll) = begin
  body, = flatten_unionall(x)
  @dom[:span
    [:span class="syntax--support syntax--type" body.name.name]
    [:span "{" interleave(map(brief_param, body.parameters), ",")... "}"]]
end
brief_param(t::TypeVar) = @dom[:span class="syntax--keyword syntax--operator syntax--relation syntax--julia" "<:" brief(t.ub)]
brief_param(x) = brief(x)

brief(T::DataType) = begin
  @dom[:span
    [:span class="syntax--support syntax--type" T.name.name]
    if !isempty(T.parameters)
      @dom[:span css"display: inline-flex; flex-direction: row"
        [:span "{"] interleave(map(brief, T.parameters), ",")... [:span "}"]]
    end]
end

header(T::DataType) = begin
  if supertype(T) ≠ Any
    @dom[:span
      brief(T)
      [:span class="syntax--keyword syntax--operator syntax--relation syntax--julia" " <: "]
      brief(supertype(T))]
  else
    brief(T)
  end
end

brief(t::TypeVar) = @dom[:span t.name]
brief(s::Symbol) = doodle(s)

flatten_unionall(x::DataType, vars=[]) = x, vars
flatten_unionall(x::UnionAll, vars=[]) = flatten_unionall(x.body, push!(vars, x.var))
doodle(t::TypeVar) = begin
  t.ub == Any && return @dom[:span t.name]
  @dom[:span t.name [:span class="syntax--keyword syntax--operator syntax--relation syntax--julia" "<:"] brief(t.ub)]
end
header(x::UnionAll) = begin
  body, vars = flatten_unionall(x)
  vars = map(doodle, vars)
  @dom[:span header(body)
    [:span class="syntax--keyword syntax--other" css"padding: 0 0.5em" "where"]
    length(vars) == 1 ? vars[1] : @dom[:span "{" interleave(vars, ",")... "}"]]
end

doodle(T::Union{DataType,UnionAll}) = begin
  attrs = fields(T)
  isempty(attrs) && return header(T)
  expandable(header(T)) do
    @dom[vstack
      Atom.CodeTools.hasdoc(T) ? doodle(Base.doc(T)) : nothing
      [vstack css"padding: 3px 5px; background: white; border-radius: 3px; margin: 3px 0"
        (@dom[hstack
          [:span String(name)]
          [:span "::"]
          brief(fieldtype(T, name))]
        for name in attrs)...]
      expandable(@dom[:h4 "Constructors"]) do
        name = @dom[:span class="syntax--support syntax--function" unwrap(T).name.name]
        @dom[vstack (render_method(m, name=name) for m in methods(T))...]
      end
      expandable(@dom[:h4 "Instance Methods"]) do
        ms = methodswith(T)
        isempty(ms) && return @dom[:span "No methods for this type"]
        @dom[vstack map(doodle, ms)...]
      end]
  end
end

unwrap(u::UnionAll) = unwrap(u.body)
unwrap(u::DataType) = u

doodle(::Type{T}) where T <: Tuple = brief(T)
doodle(u::Type{Union{}}) = @dom[:span "Union{}"]
doodle(u::Union) = brief(u)

doodle(e::Enum) = @dom[:span string(nameof(typeof(e))) "::" string(e)]
doodle(E::Type{<:Enum}) = @dom[:span string(nameof(E)) "::(" join(map(string, instances(E)), ", ") ")"]

fields(T) = try fieldnames(T) catch; () end

fade(s) = @dom[:span class="fade" s]

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
  onmousedown(e) = begin
    Atom.@msg openFile(path, line-1)
    stop[] = true
  end
  @dom[:a{onmousedown} Atom.appendline(name, line)]
end

brief(f::StackTraces.StackFrame) = begin
  f.linfo isa Nothing && return @dom[:span string(f.func)]
  f.linfo isa Core.CodeInfo && return @dom[:span repr(f.linfo.code[1])]
  @dom[:span replace(sprint(Base.show_tuple_as_call, f.linfo.def.name, f.linfo.specTypes),
                     r"^([^(]+)\(.*\)$"=>s"\1")]
end

doodle(trace::StackTraces.StackTrace) = begin
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

doodle(m::Method) = render_method(m)
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

doodle(m::Base.MethodList) = begin
  ms = collect(m)
  isempty(ms) && return @dom[:span name(m) " has no methods"]
  length(ms) == 1 && return doodle(ms[1])
  @dom[vstack map(doodle, ms)...]
end

brief(m::Base.MethodList) = @dom[:span name(m) " has $(length(collect(m))) methods"]
body(m::Base.MethodList) = @dom[vstack (doodle(method) for method in m)...]

doodle(f::Function) = @dom[vstack brief(f) body(f)]
brief(f::Function) = name(f)
body(f::Function) = begin
  @dom[:div css"""
            max-width: 800px
            white-space: normal
            h1 {font-size: 1.4em}
            pre {padding: 0}
            > div:last-child > div:last-child {overflow: visible}
            """
    Atom.CodeTools.hasdoc(f) ? @dom[:div css"padding: 8px 0" doodle(Base.doc(f))] : nothing
    [:div css"padding-left: 1em" doodle(methods(f))]]
end

isanon(f) = occursin('#', String(nameof(f)))
name(f::Function) = @dom[:span class=syntax_class(f) isanon(f) ? "λ" : String(nameof(f))]

# Markdown is loose with its types so we need special functions `renderMD`
doodle(m::Markdown.MD) =
  @dom[:div
    css"""
    max-width: 50em
    margin: 0 auto
    padding: 1.5em
    white-space: normal
    font: 1em/1.6em helvetica-light, sans-serif
    code.inline
      font-family: SourceCodePro-light
      border-radius: 3px
      padding: 0px 8px
      background: #f9f9f9
      border: 1px solid #e8e8e8
    h1, h2, h3, h4
      font-weight: 600
      margin: 0.5em 0
    h1 {font-size: 2em; margin: 1.5em 0}
    h2 {font-size: 1.5em}
    h3 {font-size: 1.25em}
    ul, ol
      margin: 0
      padding-left: 2em
      li {line-height: 1.5em; margin: 0.4em 0}
      li p {margin: 0}
      ul > li {list-style: circle; margin: 0}
      ul > li > *, ol > li > * {margin: 0}
    blockquote
      padding: 0 1em
      color: #6a737d
      border-left: .25em solid #dfe2e5
    p, blockquote {margin-bottom: 1em}
    """
    map(renderMD, CodeTools.flatten(m).content)...]

doodle(x::Union{AbstractDict,AbstractVector,Set}) = isempty(x) ? brief(x) : @dom[vstack brief(x) body(x)]

doodle(a::AbstractMatrix) =
  @dom[:table css"""
              display: grid
              border: 1px solid lightgrey
              margin: 0.5em 0
              border-radius: 5px
              background: rgb(250,250,250)
              td {padding: 0.4em 1em}
              tr:nth-child(even) {background: rgb(235,235,235)}
              tr > td:first-child {padding-left: 1em}
              """
    [:tbody
      (@dom[:tr (@dom[:td doodle(x)] for x in row)...] for row in eachrow(a))...]]

body(dict::AbstractDict) =
  @dom[vstack css"padding-left: 1em"
    (@dom[:div css"display: flex"
      doodle(key)
      [:span css"padding: 0 10px" "→"]
      doodle(value)]
    for (key, value) in dict)...]

doodle(t::NamedTuple) = literal(t)
doodle(t::Tuple) = literal(t)

literal(t::Tuple) = begin
  content = collect(interleave(map(doodle, t), @dom[:span css"padding: 0 6px 0 0" ',']))
  length(content) == 1 && push!(content, @dom[:span ','])
  @dom[hstack [:span '('] content... [:span ')']]
end

literal(t::NamedTuple) = begin
  items = (@dom[hstack string(k) '=' doodle(t[k])] for k in keys(t))
  content = collect(interleave(items, @dom[:span css"padding: 0 6px 0 0" ',']))
  length(content) == 1 && push!(content, @dom[:span ','])
  @dom[hstack [:span '('] content... [:span ')']]
end

body(s::Set) = @dom[vstack (doodle(v) for v in s)...]

brief(nt::NamedTuple) =
  @dom[:span
    [:span class="syntax--support syntax--type" "NamedTuple"]
    [:span css"color: rgb(104, 110, 122)" "[$(length(nt))]"]]

body(nt::NamedTuple) =
  @dom[vstack
    (@dom[hstack String(key) [:span css"padding: 0 5px" "="] doodle(nt[key])] for key in keys(nt))...]

body(v::Union{Tuple,AbstractVector}) = @dom[vstack map(doodle, v)...]

expandable(thunk, head) = @dom[vstack head thunk()]

doodle(e::Atom.EvalError) = begin
  trace = Atom.cliptrace(Atom.errtrace(e))
  head = @dom[:strong class="error-description" ansi(sprint(showerror, e.err))]
  isempty(trace) && return head
  @dom[:div head doodle(trace)]
end

doodle(e::Expr) = begin
  html = Atom.@rpc highlight((src=serialize(e), grammar="source.julia", block=true))
  font = Atom.@rpc config("editor.fontFamily")
  dom = parse(MIME("text/html"), html)
  dom.attrs[:style] = Dict("fontFamily" => font)
  dom.attrs[:class] = Set([css"""
                           display: flex
                           flex-direction: column
                           background: none
                           border-radius: 5px
                           padding: 0.3em
                           margin: 0
                           """])
  dom
end

doodle(bits::BitVector) = @dom[:span "BitVector[" doodle(length(bits)) "] " map(doodle∘Int, bits)...]
