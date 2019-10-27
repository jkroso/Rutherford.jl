@require "github.com/jkroso/Prospects.jl" assoc get push need dissoc Field @struct @mutable
@require "github.com/jkroso/DynamicVar.jl" @dynamic!

abstract type AbstractEntity end

"An Entity represents something who's value can change over time"
@mutable Entity(value::Any, uuid=Base.UUID(rand(UInt128)), onchange::Tuple=()) <: AbstractEntity

"Enables you to present part of an Entity as if it was an Entity in its own right"
abstract type AbstractCursor <: AbstractEntity end
@struct Cursor(parent::AbstractEntity, key::Any) <: AbstractCursor
@struct KeyCursor(value, parent::AbstractEntity) <: AbstractCursor
@struct FieldTypeCursor(value, parent::AbstractEntity) <: AbstractCursor
@struct DictIterationCursor(value::Pair, index, parent::AbstractEntity) <: AbstractCursor
@struct NTIterationCursor(value, index, parent::AbstractEntity) <: AbstractCursor
@struct IndexableIterationCursor(value, key, parent::AbstractEntity) <: AbstractCursor

need(e::AbstractEntity) = e.value
onchange(fn, e::Entity) = e.onchange = push(e.onchange, fn)
Base.getproperty(e::Entity, f::Symbol) = getproperty(e, Field{f}())
Base.setproperty!(e::Entity, f::Symbol, x) = setproperty!(e, Field{f}(), x)
Base.setproperty!(e::Entity, ::Field{:value}, x) = begin
  e.value == x && return x
  setfield!(e, :value, x)
  for f in e.onchange
    f()
  end
  x
end

Base.getproperty(e::Cursor, f::Symbol) = getproperty(e, Field{f}())
Base.getproperty(e::Cursor, ::Field{:value}) = get(getfield(e, :parent).value, getfield(e, :key))
Base.setproperty!(e::Cursor, f::Symbol, x) = setproperty!(e, Field{f}(), x)
Base.setproperty!(e::Cursor, f::Field{:value}, x) = begin
  p = getfield(e, :parent)
  p.value = assoc(p.value, getfield(e, :key), x)
end

Base.getindex(e::AbstractEntity, key) = Cursor(e, key)
Base.setindex!(e::AbstractEntity, value, key) = e.value = assoc(e.value, key, value)

Base.delete!(c::AbstractEntity) = c.value = nothing
Base.delete!(c::AbstractEntity, key) = c.value = dissoc(c.value, key)
Base.delete!(c::Cursor) = c.parent.value = dissoc(c.parent.value, c.key)

Base.length(e::AbstractEntity) = length(e.value)
Base.keys(e::AbstractEntity) = (KeyCursor(k, e) for k in keys(e.value))
Base.values(e::AbstractEntity) = (Cursor(e, k) for (k,v) in pairs(e.value))
Base.iterate(e::AbstractEntity) = iterate(e, (1, cursor_type(e.value), iterate(e.value)))
Base.eltype(e::AbstractEntity) = AbstractCursor
Base.iterate(e::AbstractEntity, (index, Cursor, subiter)) =
  if subiter != nothing
    (value, next) = subiter
    (Cursor(value, index, e), (index + 1, Cursor, iterate(e.value, next)))
  end

Base.iterate(c::NTIterationCursor) = iterate(c, :key)
Base.iterate(c::NTIterationCursor, state) =
  if state == :key
    value = keys(c.parent.value)[c.index]
    value, :value
  else
    c.value, nothing
  end

"Maps an object to the type of cursor it should produce during iteration"
cursor_type(::AbstractDict) = DictIterationCursor
cursor_type(::NamedTuple) = NTIterationCursor
cursor_type(::Union{AbstractVector,Tuple,Pair}) = IndexableIterationCursor
cursor_type(::Set) = IndexableIterationCursor # TODO: implement properly
