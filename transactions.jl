@require "github.com/MikeInnes/MacroTools.jl" => MacroTools @match
@require "github.com/jkroso/DynamicVar.jl" @dynamic!
@require "github.com/jkroso/Prospects.jl" assoc need
@require "./State.jl" UIState cursor Cursor currentUI TopLevelCursor

"Reverse the affect of a change"
function undo end

abstract type Change end

struct Merge <: Change
  data::Any
end

struct Assoc <: Change
  key::Any
  value::Any
end

"""
apply a change to `x` if `a` isn't a change then it's assumed to be a literal
value which replaces `b`
"""
apply(a, b) = a

apply(m::Merge, data) =
  reduce(pairs(m.data), init=data) do out, (key, value)
    assoc(out, key, apply(value, get(data, key)))
  end

apply(a::Assoc, data) = begin
  value = apply(a.value, get(data, a.key))
  assoc(data, a.key, value)
end

"""
Convert a change designed to be applied to a `Cursor` to one that can be applied
to a `TopLevelCursor`
"""
globalize(c::Change, cursor::TopLevelCursor) = c
globalize(c::Change, cursor::Cursor) = begin
  key = getfield(cursor, :key)
  parent = getfield(cursor, :parent)
  globalize(Assoc(key, c), parent)
end


"""
Define an event handler that calls the function you define and places the value
you return on `cursor[]`

```julia
@dom[:div onmousemove=@handler event -> event.x]
```
"""
macro handler(expr)
  fn = @match expr begin
    (f_(event_, path_) -> body_) => expr
    (f_(event_) = body_) => :($f($event, _) = $body)
    (f_() = body_) => :($f(_, __) = $body)
  end
  :(EventHandler(cursor[], $(esc(fn))))
end

struct EventHandler <: Function
  cursor::UIState
  fn::Function
end

function (handler::EventHandler)(event, path)
  @dynamic! let cursor = handler.cursor
    handler.fn(event, path)
  end
end

"Parse a `Change`"
macro change(expr)
  transform(expr)
end

"Parse a `Change` and apply it to the state of the `currentUI`"
macro transact(expr)
  quote
    change = globalize($(transform(expr)), cursor[])
    ui = currentUI[]
    put!(ui.data, apply(change, need(ui.data)))
    nothing
  end
end

const types = (merge=Merge, assoc=Assoc)

transform(s::Symbol) = esc(s)
transform(x) = x
transform(expr::Expr) =
  @match expr begin
    (f_(params__)) => :($(types[f])($(map(transform_param, params)...)))
    _ => error("unknown format $(repr(expr))")
  end

transform_param(expr) = begin
  @match expr begin
    (_(__)) => transform(expr)
    (kvs__,) => Expr(:tuple, map(transform_kv, kvs)...)
    _ => esc(expr)
  end
end

transform_kv(kv) = begin
  @match kv begin
    (k_=v_) => :($(transform(k))=$(transform(v)))
    _ => error("unknown format $kv")
  end
end
