@require "github.com/jkroso/Prospects.jl" need assoc assoc_in dissoc @mutable @struct
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
@mutable TopLevelCursor{T}(value::T, UIs=[]) <: UIState{T}
TopLevelCursor(v::T) where T = TopLevelCursor{T}(v)

Base.put!(s::TopLevelCursor, value) = begin
  setfield!(s, :value, value)
  foreach(display, getfield(s, :UIs))
end

"""
The idea of a Cursor to be able to select part of a larger data structure and pass that to a
function without it caring or even knowing that it only has part of the data. This enables
UI components to developed without caring what the overal schema of your app's data will be.
"""
@struct Cursor{T}(parent::UIState, key, value::T) <: UIState{T}

Base.getproperty(s::UIState, k::Symbol) = getproperty(need(s), k)
Base.propertynames(c::UIState) = propertynames(need(c))

need(s::UIState) = getfield(s, :value)
Base.put!(c::Cursor, value) = assoc_in!(getfield(c, :parent), Cons(getfield(c, :key)), value)
Base.getindex(c::UIState, key::Any) = Cursor(c, key, need(c)[key])
Base.setindex!(c::UIState, value, key) = assoc_in!(c, Cons(key), value)
assoc_in!(c::Cursor, keys, value) = begin
  assoc_in!(getfield(c, :parent), Cons(getfield(c, :key), keys), value)
end
assoc_in!(s::UIState, keys, value) = put!(s, assoc_in(need(s), keys => value))
Base.delete!(c::Cursor) = delete!(getfield(c, :parent), getfield(c, :key))
Base.delete!(c::Cursor, key) = put!(c, dissoc(need(c), key))

Base.iterate(s::UIState) = begin
  p = pairs(need(s))
  iterate(s, (p, iterate(p)))
end

Base.iterate(s::UIState, (pairs, next)) = begin
  next == nothing && return nothing
  (key, value), state = next
  (Cursor(s, key, value), (pairs, iterate(pairs, state)))
end

"""
`put!` a new value onto `state` by running its current value through `fn`
"""
swap(fn, state::UIState) = begin
  value = fn(need(state))
  value != nothing && put!(state, value)
end

"""
Does the same job as `swap()` but with less typing. You can write:

```julia
@swap cursor cursor + 1
```

Instead of:

```julia
swap(cursor) do i
  i + 1
end
```
"""
macro swap(cursor, expr)
  cursor = esc(cursor)
  temp = esc(gensym(:cursor))
  data = esc(gensym(:data))
  :(let $temp=$cursor,
        $cursor=need($temp),
        $data=$(esc(expr))
    $data != nothing && put!($temp, $data)
  end)
end

Base.pathof(c::Cursor) = push!(pathof(getfield(c, :parent)), getfield(c, :key))
Base.pathof(::TopLevelCursor) = []

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
