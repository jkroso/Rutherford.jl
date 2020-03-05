@use "github.com" [
  "MikeInnes/MacroTools.jl" rmlines @capture
  "jkroso" [
    "DOM.jl" => DOM @dom @css_str
    "Prospects.jl" assoc interleave
    "Destructure.jl" @destruct
    "DynamicVar.jl" @dynamic!]
  "JunoLab" [
    "CodeTools.jl" => CodeTools
    "Atom.jl" => Atom]]
@use "." msg @component Context draw doodle path data stop
@use "./markdown" renderMD
using InteractiveUtils
import Markdown
import Dates

"Formats long numbers with commas seperating it into chunks"
seperate(value::Number; kwargs...) = seperate(string(convert(Float64, value)), kwargs...)
seperate(value::Integer; kwargs...) = seperate(string(value), kwargs...)
seperate(str::String, sep = ",", k = 3) = begin
  parts = split(str, '.')
  str = parts[1]
  n = length(str)
  groups = (str[max(x-k+1, 1):x] for x in reverse(n:-k:1))
  whole_part = @dom[:span interleave(groups, @dom[:span css"color: grey" sep])...]
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

doodle(n::Union{AbstractFloat,Integer}) = @dom[:span class="syntax--language syntax--julia syntax--constant syntax--numeric" seperate(n)]
doodle(x::Union{Regex,Symbol,Char,VersionNumber,Nothing,Number,Missing}) = syntax(x)
doodle(b::Bool) = syntax(b)
doodle(d::Dates.Date) = @dom[:span Dates.format(d, Dates.dateformat"dd U Y")]
doodle(d::Dates.DateTime) = @dom[:span Dates.format(d, Dates.dateformat"dd/mm/Y H\h M\m S.s\s")]
doodle(d::Dates.Time) = @dom[:span Dates.format(d, Dates.dateformat"HH:MM:S.s")]

doodle(s::AbstractString) =
  if occursin(r"\n", s)
    @dom[vstack class="syntax--string syntax--quoted syntax--triple syntax--double syntax--julia"
      [:span "\"\"\""]
      [:span css"white-space: pre" s "\"\"\""]]
  else
    syntax(s)
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

getfile(m::Module) = begin
  if pathof(m) != nothing
    return pathof(m)
  end
  for (file, mod) in Kip.modules
    mod === m && return file
  end
end

issubmodule(m::Module) = parentmodule(m) != m && parentmodule(m) != Main
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

doodle(m::Module) = begin
  readme = nothing
  header = if issubmodule(m)
    brief(m)
  else
    file = getfile(m)
    readme = getreadme(file)
    @dom[:span brief(m) " from " stacklink(file, 0)]
  end
  expandable(header) do
    @dom[vstack css"max-width: 1000px"
      if readme != nothing
        expandable(@dom[:h3 "Readme.md"]) do
          @dom[:div css"margin-bottom: 20px" drawMDFile(readme)]
        end
      end
      (@dom[hstack
        [:span String(name)]
        [:span css"padding: 0 10px" "→"]
        isdefined(m, name) ? @dom[PropertyValue key=name] : fade("#undef")]
      for name in names(m, all=true) if !occursin('#', String(name)) && name != nameof(m))...]
  end
end

drawMDFile(path) = resolveLinks(doodle(Markdown.parse_file(path, flavor=Markdown.github)), dirname(path))

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
doodle(data::T) where T = begin
  attrs = propertynames(data)
  isempty(attrs) ? brief(T) : @dom[Expandable]
end

@component PropertyName
@component PropertyValue
data(ctx::Context{PropertyName}) = propertynames(data(ctx.parent))[path(ctx)]
path(c::PropertyName) = c.attrs[:index]
doodle(::PropertyName, name) = @dom[:span string(name)]

brief(data::T) where T = @dom[:span brief(T) '[' length(propertynames(data)) ']']
body(data::T) where T = begin
  @dom[vstack
    (@dom[hstack
      [PropertyName index=i]
      [:span css"padding: 0 10px" "→"]
      hasproperty(data, field) ? @dom[PropertyValue key=field] : fade("#undef")]
     for (i, field) in enumerate(propertynames(data)))...]
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
brief(s::Symbol) = doodle(s)

doodle(x::UnionAll) = doodle(x.body)

@component FieldType
data(ctx::Context{FieldType}) = fieldtype(data(ctx.parent), path(ctx))
path(c::FieldType) = c.attrs[:name]

doodle(T::DataType) = begin
  attrs = fields(T)
  isempty(attrs) && return header(T)
  expandable(header(T)) do
    @dom[vstack
      Atom.CodeTools.hasdoc(T) ? doodle(Base.doc(T)) : nothing
      [vstack css"padding: 3px 5px; background: white; border-radius: 3px; margin: 3px 0"
        (@dom[hstack
          [:span String(name)]
          [:span "::"]
          [FieldType name=name]]
        for name in attrs)...]
      expandable(@dom[:h4 "Constructors"]) do
        name = @dom[:span class="syntax--support syntax--function" string(T.name.name)]
        @dom[vstack (render_method(m, name=name) for m in methods(T))...]
      end
      expandable(@dom[:h4 "Instance Methods"]) do
        ms = methodswith(toUnionAll(T), supertypes=true)
        isempty(ms) && return @dom[:span "No methods for this type"]
        @dom[vstack map(doodle, ms)...]
      end]
  end
end

doodle(::Type{T}) where T <: Tuple = brief(T)
doodle(u::Type{Union{}}) = @dom[:span "Union{}"]
doodle(u::Union) = brief(u)

toUnionAll(T::DataType) = T.name.wrapper
toUnionAll(U::UnionAll) = U

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
    open(path, line)
    stop[] = true
  end
  @dom[:a{onmousedown} Atom.appendline(name, line)]
end

open(file, line) = msg("open", (file=file, line=line-1))

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
  @dom[Expandable]
end

brief(m::Base.MethodList) = @dom[:span name(m) " has $(length(collect(m))) methods"]
body(m::Base.MethodList) = @dom[:div (@dom[:div doodle(method)] for method in m)...]

@component MethodListView
data(ctx::Context{MethodListView}) = methods(data(ctx.parent))

doodle(f::Function) = @dom[Expandable]
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
    [MethodListView]]
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
    font: 17px/1.5em helvetica-light, sans-serif
    code.inline
      font-family: SourceCodePro-light
      border-radius: 3px
      padding: 0px 8px
      background: #f9f9f9
      border: 1px solid #e8e8e8
    code > .highlight > pre
      font: 0.9em SourceCodePro-light
      padding: 1em
      margin: 0
    h1, h2, h3, h4
      font-weight: 600
      margin: 0.5em 0
    h1 {font-size: 2em; margin: 1.5em 0}
    h2 {font-size: 1.5em}
    h3 {font-size: 1.25em}
    ul, ol
      margin: 1em 0
      padding-left: 2em
      ul, ol {margin: 0}
      li {line-height: 1.5em}
      li p {margin-bottom: 0}
      ul > li {list-style: circle}
    blockquote
      padding: 0 1em
      color: #6a737d
      border-left: .25em solid #dfe2e5
    p, blockquote {margin-bottom: 1em}
    """
    map(renderMD, CodeTools.flatten(m).content)...]

doodle(x::Union{AbstractDict,AbstractVector,Set}) = isempty(x) ? brief(x) : @dom[Expandable]

@component DictKey
@component DictValue
@component IndexedItem
@component SetItem

data(ctx::Context{SetItem}) = ctx.node.attrs[:value]
data(ctx::Context{DictKey}) = collect(keys(data(ctx.parent)))[path(ctx)]

body(dict::AbstractDict) =
  @dom[:div
    (@dom[:div css"display: flex"
      [DictKey key=i]
      [:span css"padding: 0 10px" "→"]
      [DictValue key=key]]
    for (i,key) in enumerate(keys(dict)))...]

doodle(t::NamedTuple) = length(t) < 5 ? literal(t) : @dom[Expandable]
doodle(t::Tuple) = length(t) < 10 ? literal(t) : @dom[Expandable]

literal(t::Tuple) = begin
  items = (@dom[IndexedItem key=i] for i in 1:length(t))
  content = collect(interleave(items, @dom[:span css"padding: 0 6px 0 0" ',']))
  length(content) == 1 && push!(content, @dom[:span ','])
  @dom[hstack [:span '('] content... [:span ')']]
end

literal(t::NamedTuple) = begin
  items = (@dom[hstack string(k) '=' [DictValue key=k]] for k in keys(t))
  content = collect(interleave(items, @dom[:span css"padding: 0 6px 0 0" ',']))
  length(content) == 1 && push!(content, @dom[:span ','])
  @dom[hstack [:span '('] content... [:span ')']]
end

body(s::Set) = @dom[vstack (@dom[SetItem value=v] for v in s)...]

brief(nt::NamedTuple) =
  @dom[:span
    [:span class="syntax--support syntax--type" "NamedTuple"]
    [:span css"color: rgb(104, 110, 122)" "[$(length(nt))]"]]

body(nt::NamedTuple) =
  @dom[vstack
    (@dom[hstack String(key) [:span css"padding: 0 5px" "="] [IndexedItem key=key]] for key in keys(nt))...]

body(v::Union{Tuple,AbstractVector}) =
  @dom[vstack (@dom[IndexedItem key=i] for i in keys(v))...]

"Shows a brief view that can be toggled into a more detailed view"
@component Expandable(state=false)
doodle(e::Expandable, data) = begin
  isopen = e.state
  @dom[:div
    [hstack css"align-items: center" onmousedown=(_)->e.state = !isopen
      chevron(isopen)
      haskey(e.attrs, :head) ? e.attrs[:head] : brief(data)]
    if isopen
      @dom[:div css"padding: 0 0 3px 20px; overflow: auto; max-height: 500px"
        haskey(e.attrs, :thunk) ? e.attrs[:thunk]() : body(data)]
    end]
end

expandable(thunk, head) = @dom[Expandable thunk=thunk head=head]

doodle(e::Atom.EvalError) = begin
  trace = Atom.cliptrace(Atom.errtrace(e))
  head = @dom[:strong class="error-description" color(sprint(showerror, e.err))]
  isempty(trace) && return head
  @dom[:div head doodle(trace)]
end

"Handle ANSI color sequences"
color(str) = begin
  matches = eachmatch(r"\e\[(\d{2})m", str)|>collect
  isempty(matches) && return @dom[:span str]
  out = [@dom[:span style.color="lightgray" str[1:matches[1].offset-1]]]
  for (i, current) in enumerate(matches)
    start = current.offset+length(current.match)
    cutoff = i == lastindex(matches) ? lastindex(str) : matches[i+1].offset-1
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

doodle(e::Expr) = expr(e)

expr(e::Expr) = expr(e, Val(e.head))
expr(e::Any) = @dom[:span css"color: #383a42" bracket('(') doodle(e) bracket(')')]
expr(r::GlobalRef) = @dom[:span string(r)]
expr(s::Symbol) =
  if context[] == :ref && s == :end
    @dom[:span class="syntax--constant syntax--numeric syntax--julia" "end"]
  elseif s == :nothing
    @dom[:span class="syntax--constant syntax--language syntax--julia" "nothing"]
  else
    @dom[:span class="syntax--language syntax--julia" s]
  end
expr(n::Union{Number,String,Char}) = doodle(n)
expr(q::QuoteNode) =
  if q.value isa Symbol
    ast = Meta.parse(repr(q.value))
    if ast isa QuoteNode
      @dom[:span class="syntax--constant syntax--other syntax--symbol syntax--julia" repr(q.value)]
    else
      expr(ast)
    end
  else
    @dom[:span ':' bracket('(') doodle(q.value) bracket(')')]
  end

expr(string, ::Val{:string}) = begin
  @dom[:span class="syntax--string syntax--quoted syntax--double syntax--julia"
    [:span class="syntax--punctuation syntax--definition syntax--string syntax--begin syntax--julia" '"']
    map(render_interp, string.args)...
    [:span class="syntax--punctuation syntax--definition syntax--string syntax--end syntax--julia" '"']]
end

render_interp(x::String) = x
render_interp(x) =
  @dom[:span class="syntax--variable syntax--interpolation syntax--julia"
    if x isa Symbol
      @dom[:span "\$$x"]
    else
      @dom[:span "\$(" doodle(x) ')']
    end]

expr(q, ::Val{:quote}) = begin
  @dom[:div
    [:span class="syntax--keyword syntax--other syntax--julia" "quote"]
    [:div css"padding-left: 1em; display: flex; flex-direction: column"
      map(expr, rmlines(q).args)...]
    end_block]
end

expr(dolla, ::Val{:$}) = begin
  value = dolla.args[1]
  @dom[:span
    [:span class="syntax--keyword syntax--operator syntax--interpolation syntax--julia" '$']
    if value isa Union{Symbol,Number}
      expr(value)
    else
      @dom[:span bracket('(') expr(value) bracket(')')]
    end]
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

expr(e, ::Val{:(::)}) =
  if length(e.args) > 1
    @dom[:span expr(e.args[1]) coloncolon type(e.args[2])]
  else
    @dom[:span coloncolon type(e.args[1])]
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

expr(fn, ::Val{:->}) = begin
  tuple,body = fn.args
  @dom[:div
    expr(tuple)
    [:span class="syntax--keyword syntax--operator syntax--arrow syntax--julia" "->"]
    expr(body)]
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
    interleave(map(expr, t.args), comma_seperator) |> collect
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
expr(c, ::Val{:const}) = @dom[:span css"> :last-child {display: inline-flex}" kw_const ' ' expr(c.args[1])]
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
