@require "github.com/jkroso/Prospects.jl" need assoc assoc_in dissoc
@require "github.com/jkroso/DynamicVar.jl" @dynamic!
@require "github.com/jkroso/Sequences.jl" Cons

@dynamic! state = nothing

"""
StateContainers manage the lifecycle of data in some way
"""
abstract type StateContainer{T} end

"""
State stores the current state of a UI and provides access to all future states. One State
object can be used in multiple UIs. Conceptually State objects are an MVP for reifying time
in your app.
"""
mutable struct State <: StateContainer{Any}
  value::Any
  UIs::Vector
end

Base.put!(s::State, value) = begin
  setfield!(s, :value, value)
  foreach(display, getfield(s, :UIs))
end

"""
The idea of a Cursor to be able to select part of a larger data structure and pass that to a
function without it caring or even knowing that it only has part of the data. This enables
UI components to developed without caring what the overal schema of your app's data will be.
"""
struct Cursor{T} <: StateContainer{T}
  parent::StateContainer
  key::Any
  value::T
end

Base.getproperty(s::StateContainer, k::Symbol) = getproperty(need(s), k)
Base.propertynames(c::StateContainer) = propertynames(need(c))

need(s::StateContainer) = getfield(s, :value)
Base.put!(c::Cursor, value) =
  assoc_in!(getfield(c, :parent), Cons(getfield(c, :key)), value)
Base.getindex(c::StateContainer, key::Any) = Cursor(c, key, need(c)[key])
Base.setindex!(c::StateContainer, value, key) = assoc_in!(c, Cons(key), value)
assoc_in!(c::Cursor, keys, value) =
  assoc_in!(getfield(c, :parent), Cons(getfield(c, :key), keys), value)
assoc_in!(s::State, keys, value) = put!(s, assoc_in(need(s), keys => value))
Base.delete!(c::Cursor) = delete!(getfield(c, :parent), getfield(c, :key))
Base.delete!(c::Cursor, key) = put!(c, dissoc(need(c), key))

Base.iterate(s::StateContainer) = begin
  p = pairs(need(s))
  iterate(s, (p, iterate(p)))
end

Base.iterate(s::StateContainer, (pairs, next)) = begin
  next == nothing && return nothing
  (key, value), state = next
  (Cursor(s, key, value), (pairs, iterate(pairs, state)))
end

"""
`put!` a new value onto `state` by running its current value through `fn`
"""
swap(fn, state::StateContainer) = begin
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
