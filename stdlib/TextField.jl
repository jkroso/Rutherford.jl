@use "github.com/jkroso/Destructure.jl" @destruct
@use ".." @dom @css_str @component emit draw TopLevelContext
@use "../transactions.jl" Swap

@component TextField(state=0)

draw(t::TextField, value) = begin
  @destruct {placeholder="Type here", attrs...} = t.attrs
  onkeydown(e) = begin
    editpoint = min(length(value), t.state)
    if e.key == "Enter"
      emit(:onsubmit, value)
    elseif e.key == "Backspace"
      str = string(value[1:editpoint-1], value[editpoint+1:end])
      str == value && return
      t.state = max(editpoint - 1, 0)
      emit(:onchange, str)
      Swap(str)
    elseif e.key == "Delete"
      str = string(value[1:editpoint], value[editpoint+2:end])
      str == value && return
      emit(:onchange, str)
      Swap(str)
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
      emit(:onchange, str)
      Swap(str)
    end
  end
  @dom[:span{onkeydown, attrs...} isempty(value) ? placeholder : value]
end

draw(ctx::TopLevelContext, str::String) =
  @dom[:span class="syntax--string syntax--quoted syntax--double"
    [:span '"']
    [TextField focus=true]
    [:span '"']]
