@use "github.com/jkroso" [
  "Prospects.jl" assoc dissoc unshift @struct
  "DOM.jl" jsonable]

"""
A `Change` represents a transformation that could be applied to a data structure.
Its like a git diff. A one argument function can serve the same purpose but for now
I'm using a special type since it is simpler to implement methods on.
"""
abstract type Change end

# stops it sending event handlers to the JS runtime
jsonable(::Change) = false

@struct Merge(data) <: Change
Merge(;keys...) = Merge(keys)
@struct Unshift(item) <: Change
@struct Assoc(key, value) <: Change
@struct Swap(value) <: Change
@struct Delete() <: Change
@struct Identity() <: Change
@struct Dissoc(key) <: Change

Merge(;kw...) = Merge(Dict(kw...))

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
