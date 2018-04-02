##
# This example is just a minimal Todo list. It's intended to show how
# a typical app would operate over an immutable data structure
#
@require "github.com/jkroso/Rutherford.jl/stdlib" TextFeild @patch scope map_scope
@require "github.com/jkroso/Rutherford.jl" UI
@require "github.com/jkroso/Prospects.jl" unshift assoc_in assoc
@require "github.com/jkroso/DOM.jl" @dom @css_str

struct Item
  title::String
  done::Bool
end

const data = Dict(:input => Dict(:value=>"", :focused=>true),
                  :items => [Item("GST", false),
                             Item("Order pop-riveter", false),
                             Item("Write todo example", true)])

render(item::Item) =
 @dom [:div class.done=item.done
            css"""
            display: flex
            align-items: center
            padding: 10px
            border-top: 1px solid rgb(180,180,180)
            &:first-child
              border-top: none
            input
              margin: 10px
            p
              flex-grow: 1
            &.done p
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
           :checked=item.done
           :onclick=@patch assoc(item, :done, !item.done)]
   [:p item.title]
   [:button "×" :onclick=@patch delete!]]

UI(data) do data
  @dom [:div css"display: flex; justify-content: space-around; align-items: center; width: 100%; height: 100%"
    [:div css"width: 500px; align-self: flex-start; margin-top: 100px; font-family: monospace"
      [scope(TextFeild, :input)
        css"""
        width: 100%
        font: 2em/1.8em monospace
        padding: 0 .8em
        border-radius: 3px
        border: 1px solid rgb(180,180,180)
        """
        placeholder="What needs doing?"
        onsubmit=@patch txt -> begin
          isempty(txt) && return
          assoc_in(data, [:input :value] => "",
                         [:items] => unshift(data[:items], Item(txt, false)))
        end]
      [:ul css"margin: 20px 0; border: 1px solid rgb(180,180,180)"
        map_scope(render, :items)...]]]
end
