##
# This example just renders the most resent user event type as
# a string. It demonstrates the round trip latency of the system
#
@require "Sequences" Stream rest
@require "Promises" Result
@require "." rutherford
import Patchwork: Elem

guiˢ = Stream(Elem(:p, "Loading"), Result())

options = [:width => 1200,
           :height => 700,
           :frame => true,
           :console => true,
           :title => "Rutherford Example"]

eventˢ,proc = rutherford(guiˢ, options)

@schedule try
  for event in eventˢ
    global guiˢ = rest(guiˢ)
    write(guiˢ, Stream(Elem(:p, event["type"]), Result()))
    yield() # not really sure why I need to yield here
  end
catch e
  showerror(STDERR, e)
end

wait(proc)
