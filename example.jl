##
# This example just renders the most resent user event type as
# a string. It demonstrates the round trip latency of the system
#
import Rutherford: rutherford
import Patchwork: Elem

guiˢ = @task begin
  produce(Elem(:p, "Loading"))
  for event in eventˢ
    produce(Elem(:p, event["type"]))
  end
end

eventˢ,renderer = rutherford(guiˢ, [
  :width => 1200,
  :height => 700,
  :frame => true,
  :console => true,
  :title => "Rutherford Example"
])

# Wait on render task so errors are shown
wait(renderer)
