##
# This example just renders the most resent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/Cursor.jl" Cursor need
@require "github.com/jkroso/DOM.jl" Container exports...
@require ".." App Window

center_content = css"""
  display: flex
  justify-content: space-around
  align-items: center
"""

Base.convert(::Type{Container{:html}}, c::Cursor) =
  @dom [:html
    [:head stylesheets...]
    [:body class=center_content [:pre repr(need(c))]]]

const app = App("Rutherford Example")

const window = Window(app, Text("Loading"), width=1200,
                                            height=700,
                                            titleBarStyle=:hidden)

@schedule for e in window.events
  put!(window.data, Cursor(e))
end

wait(app) # keeps the process open
