##
# This example just renders the most resent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/DOM.jl/stylesheet" global_sheet reset @css_str
@require "github.com/jkroso/DOM.jl" @dom
@require "." App Window

app = App("Rutherford Example")

window = Window(app, Dict(:width => 1200,
                          :height => 700,
                          :titleBarStyle => :hidden))

class = css"""
  display: flex
  justify-content: space-around
  align-items: center
"""

const head = @dom [:head global_sheet reset]

put!(window.ui, @dom [:html head [:body class=class [:pre "Loading"]]])

for e in window.events
  put!(window.ui, @dom [:html head [:body class=class [:pre repr(e)]]])
end

wait(app) # keeps the process open
