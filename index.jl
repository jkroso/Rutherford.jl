import Patchwork: Elem, diff, jsonfmt
import Electron
import JSON

assoc(key, value, d::Dict) = begin
  d = copy(d)
  d[key] = value
  d
end

function rutherford(guiˢ::Task, options::Associative)
  port,server = listenany(3000)
  proc = start_electron(assoc(:query, [:port => port], options))
  sock = accept(server)

  @schedule try
    gui = consume(guiˢ)

    # Send over initial rendering
    write(sock, gui |> jsonfmt |> JSON.json, '\n')

    # Write patches
    for nextGUI in guiˢ
      patch = diff(gui, nextGUI) |> jsonfmt |> JSON.json
      write(sock, patch, '\n')
      gui = nextGUI
    end

    # End of stream means end of UI
    kill(proc)
    close(server)
  catch e
    showerror(STDERR, e)
  end

  # Produce a series of events
  eventˢ = @task for line in eachline(sock)
    produce(JSON.parse(line))
  end

  return eventˢ,proc
end

function start_electron(params)
  stdin,process = open(`$(Electron.path) app`, "w")
  write(stdin, JSON.json(params), '\n')
  close(stdin)
  process
end
