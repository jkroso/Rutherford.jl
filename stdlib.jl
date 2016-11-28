@require "github.com/jkroso/Prospects.jl" exports...
@require "github.com/jkroso/DOM.jl" exports...

TextField(attrs, children) = begin
  cursor = attrs[:cursor]
  onkeydown(e) = begin
    if e.key == "Enter"
      attrs[:onsubmit](need(cursor[:value]))
    elseif e.key == "Backspace"
      cursor[:value] = need(cursor[:value])[1:end-1]
    elseif length(e.key) == 1
      cursor[:value] = string(need(cursor[:value]), e.key)
    end
  end
  @dom [:input :type=:text
               :value=need(cursor[:value])
               :isfocused=need(cursor[:focused])
               :onkeydown=onkeydown
               attrs...]
end

export TextField
