@use "github.com/jkroso/Rutherford.jl" doodle draw @dom @css_str @Context [
  "transactions.jl" Delete Merge Swap Assoc Unshift get
  "stdlib" [
    "TextField.jl" TextField
    "Stack.jl" StackItem VStack]]

struct AppState
  input::String
  items::Vector
end

draw(::@Context[StackItem VStack], item) =
  @dom[:div class.done=item.done
            css"""
            display: flex
            align-items: center
            padding: 10px
            border-top: 1px solid rgb(180,180,180)
            &:first-child {border-top: none}
            input {margin: 10px}
            span {flex-grow: 1}
            &.done
              text-decoration: line-through
              color: rgb(180,180,180)
            button
              border: none
              background: none
              font-size: 1.5em
              font-weight: lighter
              color: rgb(180,180,180)
              outline: none
              &:hover {color: rgb(30,30,30)}
            """
    [:input :type=:checkbox
            checked=item.done
            onclick=Assoc(:done, !item.done)]
    [:span item.title]
    [:button "×" onclick=Delete()]]

doodle(::AppState) =
  @dom[:div css"""
            width: 500px
            margin: 10px auto
            font-family: monospace
            """
    [TextField css"""
      width: 100%
      font: 2em/1.8em monospace
      padding: 0 .8em
      border-radius: 3px
      border: 1px solid rgb(180,180,180)
      """
      focus=true
      placeholder="What needs doing?"
      key=:input
      onsubmit=txt-> if !isempty(txt)
        Merge(input=Swap(""), items=Unshift((title=txt, done=false)))
      end]
    [VStack key=:items css"""
                       border-radius: 3px
                       border: 1px solid rgb(180,180,180)
                       margin-top: 10px
                       """]]

AppState("", [(title="GST", done=false),
              (title="Order pop-riveter", done=false),
              (title="Write todo example", done=true)])
