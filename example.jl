##
# This example just renders the most resent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/DOM.jl" exports...
@require "." App Window

app = App("Rutherford Example")

window = Window(app, Dict(:width => 1200,
                          :height => 700,
                          :titleBarStyle => :hidden))

center_content = css"""
  display: flex
  justify-content: space-around
  align-items: center
"""

const head = @dom [:head stylesheets...]

put!(window, @dom [:html head [:body class=center_content [:pre "Loading"]]])

for e in window.events
  put!(window, @dom [:html head [:body class=center_content [:pre repr(e)]]])
end

wait(app) # keeps the process open
