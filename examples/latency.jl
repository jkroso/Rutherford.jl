#! ../bin/rutherford
#
# This example just renders the most recent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/Rutherford.jl" UI @ui @css_str
@require "github.com/jkroso/Rutherford.jl/transactions" Swap transact

UI("Loading") do data
  handler = e-> Swap(e) |> transact
  @ui[:div css"""
           display: flex
           justify-content: space-around
           align-items: center
           width: 100%
           height: 100%
           """
           onmousedown=handler
           onmousemove=handler
           onmouseup=handler
    [:pre repr(data)]]
end
