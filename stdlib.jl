@require "github.com/jkroso/Prospects.jl" exports...
@require "github.com/jkroso/Destructure.jl" @destruct
@require "github.com/jkroso/DOM.jl" exports...

TextFeild(attrs, children) = begin
  @destruct {cursor, rest...} = attrs
  @destruct {value, :focused=>isfocused, editpoint=length(value)} = need(cursor)
  editpoint = min(editpoint, length(value))
  onkeydown(e) = begin
    if e.key == "Enter"
      attrs[:onsubmit](value)
    elseif e.key == "Backspace"
      put!(cursor, push(need(cursor),
                        :value => string(value[1:editpoint-1], value[editpoint+1:end]),
                        :editpoint => max(editpoint - 1, 0)))
    elseif e.key == "Delete"
      cursor[:value] = string(value[1:editpoint], value[editpoint+2:end])
    elseif e.key == "ArrowLeft"
      cursor[:editpoint] = max(editpoint - 1, 0)
    elseif e.key == "Home"
      cursor[:editpoint] = 0
    elseif e.key == "ArrowRight"
      cursor[:editpoint] = min(editpoint + 1, length(value))
    elseif e.key == "End"
      cursor[:editpoint] = length(value)
    elseif length(e.key) == 1
      put!(cursor, push(need(cursor),
                        :value => string(value[1:editpoint], e.key, value[editpoint+1:end]),
                        :editpoint => editpoint + 1))
    else
      @show e
    end
  end
  @dom [:input(:type=:text, isfocused, onkeydown, selectionStart=editpoint,
                                                  selectionEnd=editpoint,
                                                  value,
                                                  rest...)]
end

export TextFeild
