@require "github.com/jkroso/Destructure.jl" @destruct
@require "github.com/jkroso/Prospects.jl" assoc need
@require "github.com/jkroso/DOM.jl" emit
@require "./transactions.jl" transact Merge Assoc
@require "." @ui cursor

"Get the default data for a UI component"
function data end

TextField(attrs, children, data=need(cursor[])) = begin
  @destruct {value, :focused=>isfocused, editpoint} = data
  onkeydown(e, path) = begin
    if e.key == "Enter"
      emit(path, :onsubmit, value)
    elseif e.key == "Backspace"
      str = string(value[1:editpoint-1], value[editpoint+1:end])
      Merge((value=str, editpoint=max(editpoint - 1, 0))) |> transact
      str == value || emit(path, :onchange, str)
    elseif e.key == "Delete"
      str = string(value[1:editpoint], value[editpoint+2:end])
      Assoc(:value, str) |> transact
      str == value || emit(path, :onchange, str)
    elseif e.key == "ArrowLeft"
      Assoc(:editpoint, max(editpoint - 1, 0)) |> transact
    elseif e.key == "Home"
      Assoc(:editpoint, 0) |> transact
    elseif e.key == "ArrowRight"
      Assoc(:editpoint, min(editpoint + 1, length(value))) |> transact
    elseif e.key == "End"
      Assoc(:editpoint, length(value)) |> transact
    elseif length(e.key) == 1
      str = string(value[1:editpoint], e.key, value[editpoint+1:end])
      Merge((value=str, editpoint=editpoint + 1)) |> transact
      emit(path, :onchange, str)
    end
  end
  @ui[:input{:type=:text,
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
