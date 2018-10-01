#! ../bin/rutherford
#
# This example just renders the most recent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/Rutherford.jl" UI need
@require "github.com/jkroso/DOM.jl" @dom @css_str

UI(Text("Loading")) do cursor
  change = e->put!(cursor, e)
  @dom[:div css"""
            display: flex
            justify-content: space-around
            align-items: center
            width: 100%
            height: 100%
            """
            onmousedown=change
            onmousemove=change
            onmouseup=change
    [:pre repr(need(cursor))]]
end
