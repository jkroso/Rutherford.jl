@require "github.com/jkroso/Prospects.jl" exports...
@require "github.com/jkroso/Destructure.jl" @const
@require "github.com/jkroso/DOM.jl" exports...

TextFeild(attrs, children) = begin
  @const {cursor, rest...} = attrs
  @const {value, :focused=>isfocused} = need(cursor)
  onkeydown(e) = begin
    if e.key == "Enter"
      attrs[:onsubmit](value)
    elseif e.key == "Backspace"
      cursor[:value] = value[1:end-1]
    elseif e.key == "ArrowLeft"
    elseif length(e.key) == 1
      cursor[:value] = string(value, e.key)
    else
      @show e
    end
  end
  @dom [:input(:type=:text, value, isfocused, onkeydown, rest...)]
end

export TextFeild
