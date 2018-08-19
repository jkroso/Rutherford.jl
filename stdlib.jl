@require "github.com/MikeInnes/MacroTools.jl" => MacroTools @match
@require "github.com/jkroso/Prospects.jl" need push assoc
@require "github.com/jkroso/Destructure.jl" @destruct
@require "github.com/jkroso/DynamicVar.jl" @dynamic!
@require "github.com/jkroso/DOM.jl" @dom emit
@require "./State.jl" State Cursor state

"""
Define an event handler that applies a patch to the scope defined
by the dynamic variable `state`. The event object will be available
as `event` within the expression you pass to the `@patch` macro.
Whatever value you return from the expression becomes the value
associated with the `state` dynamic variable.

```julia
@dom [:div onmousemove=@patch event -> event.x]
```
"""
macro patch(expr)
  fn = @match expr begin
    ((event_, path_) -> body_) => :(($event, $path) -> $body)
    ((event_) -> body_) => :(($event, _) -> $body)
    _ => :((_, __) -> $expr)
  end
  :(EventHandler(state[], $(esc(fn))))
end

struct EventHandler <: Function
  state::Union{State,Cursor}
  fn::Function
end

(p::EventHandler)(event, path) = begin
  data = p.fn(event, path)
  if data ≡ delete!
    delete!(p.state)
  elseif data !== nothing
    put!(p.state, data)
  end
end

scope(key) = (fn) -> scope(fn, key)
scope(fn, key) =
  (args...) -> @dynamic! let state = state[][key]
    fn(args...)
  end

map_scope(fn, key) = begin
  cursor = state[][key]
  map(enumerate(need(cursor))) do i
    index, item = i
    @dynamic! let state = cursor[index]
      fn(item)
    end
  end
end

TextField(attrs, children) = begin
  data = need(state[])
  @destruct {value, :focused=>isfocused, editpoint=length(value)} = data
  editpoint = min(editpoint, length(value))
  onkeydown = @patch (e, path) -> begin
    if e.key == "Enter"
      emit(path, :onsubmit, value)
    elseif e.key == "Backspace"
      push(data, :value => string(value[1:editpoint-1], value[editpoint+1:end]),
                 :editpoint => max(editpoint - 1, 0))
    elseif e.key == "Delete"
      assoc(data, :value, string(value[1:editpoint], value[editpoint+2:end]))
    elseif e.key == "ArrowLeft"
      assoc(data, :editpoint, max(editpoint - 1, 0))
    elseif e.key == "Home"
      assoc(data, :editpoint, 0)
    elseif e.key == "ArrowRight"
      assoc(data, :editpoint, min(editpoint + 1, length(value)))
    elseif e.key == "End"
      assoc(data, :editpoint, length(value))
    elseif length(e.key) == 1
      push(data, :value => string(value[1:editpoint], e.key, value[editpoint+1:end]),
                 :editpoint => editpoint + 1)
    end
  end
  @dom[:input{:type=:text,
              isfocused,
              onkeydown,
              selectionStart=editpoint,
              selectionEnd=editpoint,
              size=length(value) + 1,
              value,
              attrs...}]
end

export TextField
