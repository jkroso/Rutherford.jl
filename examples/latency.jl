#! ../bin/rutherford
#
# This example just renders the most recent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/Rutherford.jl" UI
@require "github.com/jkroso/Rutherford.jl/State.jl" swap
@require "github.com/jkroso/DOM.jl" @dom @css_str

UI("Loading") do data
  @dom[:div css"""
            display: flex
            justify-content: space-around
            align-items: center
            width: 100%
            height: 100%
            """
            onmousedown=swap
            onmousemove=swap
            onmouseup=swap
    [:pre repr(data)]]
end
