#! ../bin/rutherford
#
# This example just renders the most recent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/Rutherford.jl" UI @handler @ui @css_str

UI("Loading") do data
  @ui[:div css"""
           display: flex
           justify-content: space-around
           align-items: center
           width: 100%
           height: 100%
           """
           onmousedown=@handler e -> e
           onmousemove=@handler e -> e
           onmouseup=@handler e -> e
    [:pre repr(data)]]
end
