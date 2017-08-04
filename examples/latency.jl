##
# This example just renders the most resent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/Cursor.jl" Cursor need
@require "github.com/jkroso/DOM.jl" Container exports...
@require ".." App Window

Base.convert(::Type{Container{:html}}, c::Cursor) = begin
  change(e) = put!(c, e)
  @dom [:html
    [:head stylesheets...]
    [:body css"""
           display: flex
           justify-content: space-around
           align-items: center
           """
           onmousedown=change
           onmousemove=change
           onkeydown=change
      [:pre repr(need(c))]]]
end

const app = App("Rutherford Example")

const window = Window(app, Text("Loading"), width=1200,
                                            height=700,
                                            titleBarStyle=:hidden)

wait(app) # keeps the process open
