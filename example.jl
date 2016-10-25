##
# This example just renders the most resent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "github.com/jkroso/DOM.jl/stylesheet" global_sheet @css_str
@require "github.com/jkroso/DOM.jl" @dom
@require "." App Window

app = App("Rutherford Example")

window = Window(app, Dict(:width => 1200,
                          :height => 700,
                          :titleBarStyle => :hidden))

put!(window.ui, @dom [:html [:head global_sheet] [:body [:p "Loading"]]])

for e in window.events
  put!(window.ui, @dom [:html
    [:head global_sheet]
    [:body [:pre class=css"text-align: center" repr(e)]]
  ])
end

wait(app) # keeps the process open
