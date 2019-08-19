@require "github.com/jkroso/Prospects.jl" assoc
@require "github.com/jkroso/DOM.jl" emit
@require "." @ui default_state @component render

@component TextField
default_state(::Type{TextField}) = (editpoint=0, isfocused=false)
render(t::TextField) = begin
  value = t.cursor.value
  editpoint, isfocused = t.state
  editpoint = min(length(value), editpoint)
  onkeydown(e, path) = begin
    if e.key == "Enter"
      emit(path, :onsubmit, value)
    elseif e.key == "Backspace"
      str = string(value[1:editpoint-1], value[editpoint+1:end])
      str == value && return
      t.state = assoc(t.state, :editpoint, max(editpoint - 1, 0))
      t.cursor.value = str
      emit(path, :onchange, str)
    elseif e.key == "Delete"
      str = string(value[1:editpoint], value[editpoint+2:end])
      str == value && return
      t.cursor.value = str
      emit(path, :onchange, str)
    elseif e.key == "ArrowLeft"
      t.state = assoc(t.state, :editpoint, max(editpoint - 1, 0))
    elseif e.key == "Home"
      t.state = assoc(t.state, :editpoint, 0)
    elseif e.key == "ArrowRight"
      t.state = assoc(t.state, :editpoint, min(editpoint + 1, length(value)))
    elseif e.key == "End"
      t.state = assoc(t.state, :editpoint, length(value))
    elseif length(e.key) == 1
      str = string(value[1:editpoint], e.key, value[editpoint+1:end])
      t.state = assoc(t.state, :editpoint, editpoint + 1)
      t.cursor.value = str
      emit(path, :onchange, str)
    end
  end
  @ui[:input{:type=:text,
             isfocused=get(t.attrs, :isfocused, isfocused),
             onkeydown,
             selectionStart=editpoint,
             selectionEnd=editpoint,
             size=length(value) + 1,
             value,
             t.attrs...}]
end
