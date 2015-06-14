@require "parse-json" parse => parseJSON
@require "write-json" json => toJSON
@require "Sequences" Stream rest
@require "Promises" Result
import Patchwork: Elem, diff, jsonfmt
import Electron

assoc(key, value, d::Dict) = begin
  d = copy(d)
  d[key] = value
  d
end

function rutherford(guiˢ, options)
  port,server = listenany(3000)
  proc = start_electron(assoc(:query, [:port => port], options))
  sock = accept(server)

  # Send over initial rendering
  write(sock, guiˢ |> first |> jsonfmt |> toJSON, '\n')

  @schedule try
    # Write patches
    reduce(guiˢ) do a, b
      patch = diff(a, b) |> jsonfmt |> toJSON
      write(sock, patch, '\n')
      b
    end
    # End of stream means end of UI
    kill(proc)
    close(server)
  catch e
    showerror(STDERR, e)
  end

  # Read a stream of events from the GUI and write them to
  # the event stream
  eventˢ = Result{Stream}()
  @schedule try
    for line in eachline(sock)
      tail = Result{Stream}()
      write(eventˢ, Stream(parseJSON(line), tail))
      eventˢ = tail
    end
  catch e
    showerror(STDERR, e)
  end

  return eventˢ,proc
end

function start_electron(params)
  stdin,process = open(`$(Electron.path) app`, "w")
  write(stdin, toJSON(params), '\n')
  close(stdin)
  process
end
