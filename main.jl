@use "github.com/jkroso/DOM.jl" => DOM
@use "github.com" [
  "MikeInnes/MacroTools.jl" => MacroTools @match
  "jkroso" [
    "DOM.jl/Events.jl" => Events
    "Prospects.jl" assoc
    "Destructure.jl" @destruct]
  "JunoLab/Atom.jl" => Atom
  "JunoLab/Juno.jl" => Juno]
@use "./redesign.jl" InlineResult emit Snippet

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

const event_parsers = Dict{String,Function}(
  "mousedown" => d-> Events.MouseDown(d["path"], Events.MouseButton(d["button"]), map(round, d["position"])...),
  "mouseup" => d-> Events.MouseUp(d["path"], Events.MouseButton(d["button"]), map(round, d["position"])...),
  "mouseover" => d-> Events.MouseOver(d["path"]),
  "mouseout" => d-> Events.MouseOut(d["path"]),
  "click" => d-> Events.Click(d["path"], Events.MouseButton(d["button"]), map(round, d["position"])...),
  "dblclick" => d-> Events.DoubleClick(d["path"], Events.MouseButton(d["button"]), map(round, d["position"])...),
  "mousemove" => d-> Events.MouseMove(d["path"], map(round, d["position"])...),
  "keydown" => d-> Events.KeyDown(UInt8[], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))),
  "keyup" => d-> Events.KeyUp(UInt8[], d["key"], Set{Symbol}(map(Symbol, d["modifiers"]))),
  "resize" => d-> Events.Resize(d["width"], d["height"]),
  "scroll" => d-> Events.Scroll(d["path"], map(round, d["position"])...))

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
