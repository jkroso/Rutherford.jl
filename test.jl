@use "github.com/jkroso/Rutherford.jl" msg current_device
@use "github.com/jkroso/Rutherford.jl/draw.jl" doodle @dom @css_str color hstack vstack
@use "github.com/ssfrr/DeepDiffs.jl" deepdiff DeepDiff SimpleDiff
@use "github.com/IainNZ/Humanize.jl" datasize

struct Result
  data::Tuple
end

struct Comparison
  data::Tuple
  expected
end

macro test(x)
  if Meta.isexpr(x, :call, 3) && x.args[1] == :(==)
    :(Comparison(@timed($(esc(x.args[2]))), $(esc(x.args[3]))))
  else
    :(Result(@timed $(esc(x))))
  end
end

@eval macro $(:catch)(expr)
  quote
    (function()
      try $(esc(expr)) catch e return e end
      error("did not throw an error")
    end)()
  end
end

doodle(r::Result) = begin
  pass, time, bytes, gctime, memallocs = r.data
  pass ? notify_pass() : notify_fail()
  @dom[:span class.passed=pass
             css"""
             &.passed > span:first-child {color: rgb(0, 226, 0)}
             > span:first-child {color: red; padding-right: 6px}
             > span:nth-child(2)
               opacity: 0.6
               > span {font-size: 0.9em; opacity: 0.8}
             padding: 1px
             """
    [:span pass ? "✓" : "✗"]
    [:span round(Int, 1000time) [:span "ms "]
           string(memallocs.poolalloc) "mallocs "
           replace(datasize(bytes), ' '=>"")]]
end

doodle(c::Comparison) = begin
  a, time, bytes, gctime, memallocs = c.data
  pass = a == c.expected
  pass && return doodle(Result((true, time, bytes, gctime, memallocs)))
  notify_fail()
  @dom[hstack "💥 " doodle(deepdiff(a, c.expected))]
end

showdiff(io, diff) = show(IOContext(io, :color=>true), diff)
doodle(d::DeepDiff) = @dom[:span color(sprint(showdiff, d))]
doodle(d::SimpleDiff) = @dom[:span "got " doodle(d.before) " expected " doodle(d.after)]

notify_fail(d=current_device()) = msg("test failed", to_tuple(d.snippet))
notify_pass(d=current_device()) = msg("test passed", to_tuple(d.snippet))
to_tuple(x::T) where T = NamedTuple{fieldnames(T), Tuple{fieldtypes(T)...}}(tuple(values(x)...))
