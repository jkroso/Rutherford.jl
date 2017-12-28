##
# This example just renders the most recent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/DOM.jl" HTML @dom @css_str
@require "../stdlib" @patch
@require ".." App window

window(App("Latency Example"), Text("Loading")) do e
  change = @patch e -> e
  @dom [HTML css"""
             display: flex
             justify-content: space-around
             align-items: center
             """
             onmousedown=change
             onmousemove=change
             onkeydown=change
    [:pre repr(e)]]
end |> wait
