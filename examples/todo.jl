#! ../bin/rutherford
#
# This example is just a minimal Todo list. It's intended to show how
# a typical app would operate over an immutable data structure
#
@require "github.com/jkroso/Rutherford.jl/stdlib" TextField data
@require "github.com/jkroso/Rutherford.jl/state" Cursor @swap
@require "github.com/jkroso/Prospects.jl" unshift assoc
@require "github.com/jkroso/Rutherford.jl" UI render
@require "github.com/jkroso/DOM.jl" @dom @css_str

struct Item
  title::String
  done::Bool
end

const state = (input=assoc(data(TextField), :focused, true),
               items=[Item("GST", false),
                      Item("Order pop-riveter", false),
                      Item("Write todo example", true)])

render(item::Cursor{Item}) =
 @dom[:div class.done=item.done
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
           onclick=e->@swap item assoc(item, :done, !item.done)]
   [:span item.title]
   [:button "×" onclick=e->delete!(item)]]

UI(state) do state
  @dom[:div css"""
            display: flex
            flex-direction: column
            width: 500px
            margin: 10px
            font-family: monospace
            """
    [scope(TextField, :input)
      css"""
      width: 100%
      font: 2em/1.8em monospace
      padding: 0 .8em
      border-radius: 3px
      border: 1px solid rgb(180,180,180)
      """
      placeholder="What needs doing?"
      onsubmit=txt->@swap state begin
        isempty(txt) && return nothing
        assoc(state, :input, assoc(data(TextField), :focused, true),
                     :items, unshift(state.items, Item(txt, false)))
      end]
    [:ul css"margin: 20px 0; border: 1px solid rgb(180,180,180); padding: 0; width: 100%"
      state[:items]...]]
end
