@use "github.com/jkroso/DOM.jl" => DOM
@use "github.com" [
  "MikeInnes/MacroTools.jl" => MacroTools @match
  "jkroso" [
    "Prospects.jl" assoc
    "Destructure.jl" @destruct]
  "JunoLab/Atom.jl" => Atom
  "JunoLab/Juno.jl" => Juno]
@use "./redesign.jl" InlineResult emit Snippet

# Hacks to get completion working with Kip modules
const complete = Atom.handlers["completions"]
Atom.handle("completions") do data
  mod = Kip.get_module(data["path"], interactive=true)
  try
    complete(assoc(data, "mod", mod))
  catch end
end
const module_handler = Atom.handlers["module"]
Atom.handle("module") do data
  ret = module_handler(data)
  ret.main != "Main" && return ret
  path = get(data, "path", "")
  mod = Kip.get_module(path, interactive=true)
  assoc(ret, :main, string(mod))
end
const workspace_handler = Atom.handlers["workspace"]
Atom.handle("workspace") do mod
  file = Atom.@rpc currentfile()
  m = Kip.get_module(file, interactive=true)
  workspace_handler(string(m))
end
const ismodule = Atom.handlers["ismodule"]
Atom.handle("ismodule") do mod
  file = Atom.@rpc currentfile()
  isfile(file) || ismodule(mod)
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

Atom.handle("event") do id, data
  if haskey(inline_displays, id)
    res = Atom.@errs emit(inline_displays[id], data)
    res isa Atom.EvalError && showerror(IOContext(stderr, :limit => true), res)
  end
  nothing
end

Atom.handle("reset module") do file
  delete!(Kip.modules, file)
  Kip.get_module(file, interactive=true)
  nothing
end

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
        display(device, convert(DOM.Node, device.ui))
        @info "eval" progress=i/total _id=progress_id
      end
    end
  end
end

getblocks(data, path, src) = begin
  @destruct [[start_row, start_col], [end_row, end_col]] = data
  lines = collect(eachline(IOBuffer(src), keep=true))
  utf8 = codeunits(src)
  # full file
  if end_col == nothing
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
    start_i += ncodeunits(lines[line])
    line += 1
  end
  start_i += start_col
  end_i = start_i
  while line < end_row
    end_i += ncodeunits(lines[line])
    line += 1
  end
  blocks = Any[]
  while start_i <= end_i
    (ast, i) = Meta.parse(src, start_i)
    line = countlines(IOBuffer(utf8[1:start_i])) - 1
    text = String(utf8[start_i:i-1])
    range = [[line, 0], [line+countlines(IOBuffer(text))-1, 0]]
    push!(blocks, (text=strip(text), line=line, range=range))
    start_i = i
  end
  blocks
end
Atom.handle(getblocks, "getblocks")

Atom.handle("result done") do id
  delete!(inline_displays, id)
end
