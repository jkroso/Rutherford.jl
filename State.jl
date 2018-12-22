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

"Works as you would expect except it returns the value unwrapped"
Base.getproperty(s::UIState, k::Symbol) = getproperty(need(s), k)
Base.propertynames(c::UIState) = propertynames(need(c))

Base.getindex(c::UIState, key::Any) = Cursor(c, key, need(c)[key])
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

"""
`put!` a new value onto `cursor` by running its current value through `fn`
"""
swap(fn::Function) = begin
  value = fn(need(cursor[]))
  value != nothing && put!(cursor[], value)
end

"`put!` a new value onto `cursor`"
swap(data) = put!(cursor[], data)

Base.pathof(c::Cursor) = push!(pathof(getfield(c, :parent)), getfield(c, :key))
Base.pathof(::TopLevelCursor) = []
Base.pathof(c::KeyCursor) = push!(pathof(getfield(c, :parent)), c)

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
