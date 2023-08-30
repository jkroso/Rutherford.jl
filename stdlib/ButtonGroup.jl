@use "github.com/jkroso/DOM.jl" @css_str @dom

function button(attrs, children)
  @dom[:button{css"""
               padding: .5em .75em
               font-size: .875em
               line-height: 1.25em
               font-weight: 600
               color: rgb(17, 24, 39)
               background: white
               text-align: center
               border: 1px solid #e5e7eb
               &:hover {background: rgb(249 250 251)}
               """, attrs...} type="button" children...]
end

function button_group(attrs, children)
  @dom[:div{attrs..., css"""
                      display: inline-flex
                      > button {border-right: none}
                      > :first-child {border-radius: .375em 0 0 .375em}
                      > :last-child {border-radius: 0 .375em .375em 0; border-right: 1px solid #e5e7eb}
                      """}
    [@dom[button x] for x in children]...]
end

@dom[button_group "Years" "Months" "Days" "Hours"]
