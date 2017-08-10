##
# This example is just a minimal Todo list. It's intended to show how
# a typical app would operate over an immutable data structure
#
@require "github.com/jkroso/Prospects.jl" need unshift assoc_in
@require "github.com/jkroso/DOM.jl" Node Container exports...
@require "github.com/jkroso/Cursor.jl" Cursor
@require "../stdlib" exports...
@require ".." App Window render

struct Item
  title::String
  done::Bool
end

Base.convert(::Type{Node}, x::Cursor{Item}) =
  @dom [:div class.done=need(x[:done])
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
               &:hover
                 color: rgb(30,30,30)
             """
    [:input :type=:checkbox
            :checked=need(x[:done])
            :onclick=e->x[:done] = !x[:done]]
    [:p need(x[:title])]
    [:button "×" :onclick=e->delete!(x)]]

Base.convert(::Type{Container{:html}}, c::Cursor) =
  @dom [:html
    [:head [:title "Todo List Example"] stylesheets...]
    [:body css"display: flex; justify-content: space-around; align-items: center"
      [:div css"width: 500px; align-self: flex-start; margin-top: 100px; font-family: monospace"
        [TextFeild css"""
                   width: 100%
                   font: 2em/1.8em monospace
                   padding: 0 .8em
                   border-radius: 3px
                   border: 1px solid rgb(180,180,180)
                   """
          placeholder="What needs doing?"
          cursor=c[:input]
          onsubmit=function onsubmit(txt)
            isempty(txt) && return
            put!(c, assoc_in(need(c), [:input, :value] => "",
                                      [:items] => unshift(need(c)[:items], Item(txt, false))))
          end]
        [:ul css"margin: 20px 0; border: 1px solid rgb(180,180,180)" c[:items]...]]]]

const data = Dict(:input => Dict(:value=>"", :focused=>true),
                  :items => [Item("GST", false),
                             Item("Order pop-riveter", false),
                             Item("Write todo example", true)])

const app = App("Todo List Example", version=v"1.6.11")
const w = Window(app, data, width=1200, height=700, titleBarStyle=:hidden)

# If you want to develop this code interactively in Atom then just
# uncomment this code and comment out the `wait(app)` below
# let
#   default_handler = Atom.handlers["eval"]
#   Atom.handle("eval") do expr
#     result = default_handler(expr)
#     Base.invokelatest(render, w)
#     result
#   end
# end

wait(app) # keeps the process open
