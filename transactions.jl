@require "github.com/MikeInnes/MacroTools.jl" => MacroTools @match
@require "github.com/jkroso/DynamicVar.jl" @dynamic!
@require "github.com/jkroso/Prospects.jl" assoc need dissoc unshift
@require "./State.jl" UIState cursor Cursor currentUI TopLevelCursor

"""
A `Change` represents a transformation that could be applied to a data structure.
Its like a git diff. A one argument function can serve the same purpose but for now
I'm using a special type since it is simpler to implement methods on.
"""
abstract type Change end

struct Merge <: Change
  data::Any
end

struct Unshift <: Change
  item::Any
end

struct Assoc <: Change
  key::Any
  value::Any
end

struct Swap <: Change
  value::Any
end

struct Delete <: Change end
struct Dissoc <: Change
  key::Any
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

apply(u::Unshift, data) = unshift(data, u.item)
apply(s::Swap, data) = s.value
apply(a::Delete, data) = nothing
apply(a::Dissoc, data) = dissoc(data, a.key)

"""
Convert a change designed to be applied to a `Cursor` to one that can be applied
to a `TopLevelCursor`
"""
globalize(c::Change, cursor::TopLevelCursor) = c
globalize(c::Change, cursor::Cursor) = globalize(Assoc(getfield(cursor, :key), c), getfield(cursor, :parent))
globalize(d::Delete, c::Cursor) = globalize(Dissoc(getfield(c, :key)), getfield(c, :parent))

"`globalize` a `change` and apply it to the state of the `currentUI`"
transact(change::Change) = begin
  ui = currentUI[]
  change = globalize(change, cursor[])
  put!(ui.data, apply(change, need(ui.data)))
  nothing
end
