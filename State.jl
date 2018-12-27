@require "github.com/jkroso/Prospects.jl" need assoc assoc_in dissoc @mutable @struct
  @require "github.com/MikeInnes/MacroTools.jl" => MacroTools @match
@require "github.com/jkroso/DynamicVar.jl" @dynamic!
@require "github.com/jkroso/Sequences.jl" Cons

@dynamic! currentUI = nothing
@dynamic! cursor = nothing

"""
UIStates manage the lifecycle of data in some way
"""
abstract type UIState{T} end

"""
State stores the current state of a UI and provides access to all future states. One State
object can be used in multiple UIs. Conceptually State objects are an MVP for reifying time
in your app.
"""
@struct TopLevelCursor{T}(value::T, UIs=[]) <: UIState{T}
TopLevelCursor(v::T) where T = TopLevelCursor{T}(v)

Base.put!(s::TopLevelCursor, value) = begin
  new_cursor = TopLevelCursor(value)
  for ui in getfield(s, :UIs)
    ui.data = new_cursor
    display(ui)
  end
end

"""
The idea of a Cursor to be able to select part of a larger data structure and pass that to a
function without it caring or even knowing that it only has part of the data. This enables
UI components to developed without caring what the overal schema of your app's data will be.
"""
@struct Cursor{T}(parent::UIState, key, value::T) <: UIState{T}

"Works as you would expect except it returns the value unwrapped"
Base.getproperty(s::UIState, k::Symbol) = getproperty(need(s), k)
Base.propertynames(c::UIState) = propertynames(need(c))

Base.getindex(c::UIState, key::Any) = Cursor(c, key, get(need(c), key))
Base.setindex!(c::UIState, value, key) = assoc_in!(c, Cons(key), value)

need(s::UIState) = getfield(s, :value)
Base.put!(c::Cursor, value) = assoc_in!(getfield(c, :parent), Cons(getfield(c, :key)), value)
assoc_in!(c::Cursor, keys, value) = begin
  assoc_in!(getfield(c, :parent), Cons(getfield(c, :key), keys), value)
end
assoc_in!(s::UIState, keys, value) = put!(s, assoc_in(need(s), keys => value))
Base.delete!(c::Cursor) = delete!(getfield(c, :parent), getfield(c, :key))
Base.delete!(c::Cursor, key) = put!(c, dissoc(need(c), key))

Base.length(s::UIState) = length(need(s))
Base.keys(s::UIState) = (KeyCursor(k, s) for k in keys(need(s)))
Base.values(s::UIState) = (Cursor(s, k, v) for (k,v) in pairs(need(s)))
Base.pairs(s::UIState{<:Set}) = (KeyCursor(i, s) => Cursor(s, i, v) for (i, v) in enumerate(need(s)))
Base.iterate(s::UIState) = begin
  p = pairs(s)
  iterate(s, (p, iterate(p)))
end
Base.iterate(s::UIState, (pairs, state)) =
  if state != nothing
    value, next = state
    (value, (pairs, iterate(pairs, next)))
  end

struct KeyCursor{T} <: UIState{T}
  value::T
  parent::UIState
end

struct FieldTypeCursor{T} <: UIState{T}
  value::T
  parent::UIState
end

Base.pathof(c::Cursor) = push!(pathof(getfield(c, :parent)), getfield(c, :key))
Base.pathof(::TopLevelCursor) = []
Base.pathof(c::KeyCursor) = push!(pathof(getfield(c, :parent)), c)
Base.pathof(c::FieldTypeCursor) = push!(pathof(getfield(c, :parent)), c)

struct PrivateRef
  key::Any
  default::Any
  cursor::UIState
  ui::Any
end

_dict(r::PrivateRef) = get!(Dict, r.ui.private, pathof(r.cursor))
Base.getindex(r::PrivateRef) = get(_dict(r), r.key, r.default)
Base.setindex!(r::PrivateRef, value) = begin
  _dict(r)[r.key] = value
  display(r.ui)
end

"""
Get a reference to the private state associated with the current cursor
"""
private(key, default) = PrivateRef(key, default, cursor[], currentUI[])

"""
Define an event handler that calls the function you define and places the value
you return on `cursor[]`

```julia
@dom[:div onmousemove=@handler event -> event.x]
```
"""
macro handler(expr)
  fn = @match expr begin
    ((event_, path_) -> body_) => :(($event, $path) -> $body)
    ((event_) -> body_) => :(($event, _) -> $body)
    _ => :((_, __) -> $expr)
  end
  :(EventHandler(cursor[], $(esc(fn))))
end

struct EventHandler <: Function
  cursor::UIState
  fn::Function
end

(handler::EventHandler)(event, path) = begin
  @dynamic! let cursor = handler.cursor
    returned = handler.fn(event, path)
    if returned ≡ delete!
      delete!(handler.cursor)
    elseif returned !== nothing
      put!(handler.cursor, returned)
    end
  end
end
