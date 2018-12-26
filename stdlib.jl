@require "github.com/jkroso/Destructure.jl" @destruct
@require "github.com/jkroso/Prospects.jl" assoc
@require "github.com/jkroso/DOM.jl" @dom emit
@require "./State.jl" @handler need cursor

"Get the default data for a UI component"
function data end

TextField(attrs, children, data=need(cursor[])) = begin
  @destruct {value, :focused=>isfocused, editpoint} = data
  onkeydown = @handler (e, path) -> begin
    if e.key == "Enter"
      emit(path, :onsubmit, value)
    elseif e.key == "Backspace"
      assoc(data, :value, string(value[1:editpoint-1], value[editpoint+1:end]),
                  :editpoint, max(editpoint - 1, 0))
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
      assoc(data, :value, string(value[1:editpoint], e.key, value[editpoint+1:end]),
                  :editpoint, editpoint + 1)
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

data(::typeof(TextField)) = data(TextField, "")
data(::typeof(TextField), str::AbstractString) = (value=str, focused=false, editpoint=length(str))
