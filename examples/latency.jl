##
# This example just renders the most recent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/DOM.jl" @dom @css_str
@require "github.com/jkroso/Rutherford.jl/stdlib" @patch
@require "github.com/jkroso/Rutherford.jl" UI

UI(Text("Loading")) do e
  change = @patch e -> e
  @dom [:div css"""
             display: flex
             justify-content: space-around
             align-items: center
             width: 100%
             height: 100%
             """
             onmousedown=change
             onmousemove=change
    [:pre repr(e)]]
end
