#! ../bin/rutherford
#
# This example is just a minimal Todo list. It's intended to show how
# a typical app would operate over an immutable data structure
#
@require "github.com/jkroso/Rutherford.jl" UI render @ui @css_str cursor default_state
@require "github.com/jkroso/Rutherford.jl/transactions" Delete Assoc Unshift transact
@require "github.com/jkroso/Rutherford.jl/stdlib" TextField

struct Item
  title::String
  done::Bool
end

const state = [Item("GST", false),
               Item("Order pop-riveter", false),
               Item("Write todo example", true)]

render(item::Item) =
 @ui[:div class.done=item.done
          css"""
          display: flex
          align-items: center
          padding: 10px
          border-top: 1px solid rgb(180,180,180)
          &:first-child
            border-top: none
          input
            margin: 10px
          span
            flex-grow: 1
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
            &:hover
              color: rgb(30,30,30)
          """
   [:input :type=:checkbox
           checked=item.done
           onclick=()->transact(Assoc(:done, !item.done))]
   [:span item.title]
   [:button "×" onclick=()->transact(Delete())]]

UI(state) do state
  input = @ui[TextField
    css"""
    width: 100%
    font: 2em/1.8em monospace
    padding: 0 .8em
    border-radius: 3px
    border: 1px solid rgb(180,180,180)
    """
    placeholder="What needs doing?"
    isfocused=true
    onsubmit=txt-> if !isempty(txt)
      transact(Unshift(Item(txt, false)))
      input.state = default_state(TextField)
    end]
  @ui[:div css"""
           display: flex
           flex-direction: column
           width: 500px
           margin: 10px
           font-family: monospace
           """
    input
    [:ul css"margin: 20px 0; border: 1px solid rgb(180,180,180); padding: 0; width: 100%"
      map(render, cursor[])...]]
end
