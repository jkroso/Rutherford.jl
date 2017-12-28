@require "github.com/jkroso/Prospects.jl" need assoc assoc_in dissoc
@require "github.com/jkroso/DynamicVar.jl" @dynamic!
@require "github.com/jkroso/Sequences.jl" Cons

@dynamic! state = nothing

"""
State stores the current state of a UI and provides access to all future states. One State
object can be used in multiple UIs
"""
mutable struct State
  data::Any
  UIs::Vector
end

Base.put!(s::State, value) = begin
  s.data = value
  foreach(display, s.UIs)
end

"""
The idea of a cursor to be able to select part of a larger data structure and pass that to a
function while still enabling that function to update the structure as a whole when changes
are made to its part of the data structure
"""
struct Cursor
  parent::Union{Cursor,State}
  key::Any
end

need(c::State) = c.data
need(c::Cursor) = get(need(c.parent), c.key)
Base.put!(c::Cursor, value) = assoc_in!(c.parent, Cons(c.key), value)
Base.getindex(c::Union{Cursor,State}, key::Any) = Cursor(c, key)
Base.setindex!(c::Union{Cursor,State}, value, key) = assoc_in!(c, Cons(key), value)
assoc_in!(c::Cursor, keys, value) = assoc_in!(c.parent, Cons(c.key, keys), value)
assoc_in!(s::State, keys, value) = put!(s, assoc_in(s.data, keys => value))
Base.delete!(c::Cursor) = delete!(c.parent, c.key)
Base.delete!(c::Cursor, key) = put!(c, dissoc(need(c), key))
