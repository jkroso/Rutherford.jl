@require "github.com/jkroso/DOM.jl" => DOM propagate @css_str
@require "github.com/jkroso/Destructure.jl" @destruct
@require "." @dom default_state @component render

@component TextField
default_state(::Type{TextField}) = 0
render(t::TextField) = begin
  value = t.cursor.value
  @destruct {placeholder="Type here", attrs...} = t.attrs
  editpoint = min(length(value), t.state)
  @dom[:div{attrs...} isempty(value) ? placeholder : value]
end

DOM.emit(t::TextField, e::DOM.Events.Key{:down}) = begin
  value = t.cursor.value
  editpoint = min(length(value), t.state)
  if e.key == "Enter"
    DOM.emit(:onsubmit, value)
  elseif e.key == "Backspace"
    str = string(value[1:editpoint-1], value[editpoint+1:end])
    str == value && return
    t.state = max(editpoint - 1, 0)
    t.cursor.value = str
    DOM.emit(:onchange, str)
  elseif e.key == "Delete"
    str = string(value[1:editpoint], value[editpoint+2:end])
    str == value && return
    t.cursor.value = str
    DOM.emit(:onchange, str)
  elseif e.key == "ArrowLeft"
    t.state = max(editpoint - 1, 0)
  elseif e.key == "Home"
    t.state = 0
  elseif e.key == "ArrowRight"
    t.state = min(editpoint + 1, length(value))
  elseif e.key == "End"
    t.state = length(value)
  elseif length(e.key) == 1
    str = string(value[1:editpoint], e.key, value[editpoint+1:end])
    t.state = editpoint + 1
    t.cursor.value = str
    DOM.emit(:onchange, str)
  end
end
