#! ../bin/rutherford
#
# This example just renders the most recent user event type as
# a string. It demonstrates the round trip latency of the system
#
@use "github.com/jkroso/Rutherford.jl" doodle @dom @css_str ["transactions.jl" Assoc]

struct AppState
  event::Any
end

doodle(a::AppState) = begin
  handler = e->Assoc(:event, e)
  @dom[:div css"""
            display: flex
            justify-content: space-around
            align-items: center
            width: 900px
            height: 100px
            """
            onmousedown=handler
            onmousemove=handler
            onmouseup=handler
            onkeydown=handler
            onkeyup=handler
            focus=true
    [:pre repr(a.event)]]
end

AppState("Loading")
