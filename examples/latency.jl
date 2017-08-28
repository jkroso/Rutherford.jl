##
# This example just renders the most recent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/Cursor.jl" Cursor need
@require "github.com/jkroso/DOM.jl" Container HTML @dom @css_str
@require ".." App Window

Base.convert(::Type{Container{:html}}, c::Cursor) = begin
  change(e) = put!(c, e)
  @dom [HTML css"""
             display: flex
             justify-content: space-around
             align-items: center
             """
             onmousedown=change
             onmousemove=change
             onkeydown=change
    [:pre repr(need(c))]]
end

Window(App("Latency Example"), Text("Loading")) |> wait
