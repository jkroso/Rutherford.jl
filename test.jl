@use "github.com/jkroso/Rutherford.jl" msg current_device @dynamic!
@use "github.com/jkroso/Rutherford.jl/draw.jl" doodle @dom @css_str color hstack vstack
@use "github.com/ssfrr/DeepDiffs.jl" deepdiff DeepDiff SimpleDiff
@use "github.com/IainNZ/Humanize.jl" datasize

abstract type Test end

struct Result <: Test
  data::Tuple
end

struct Comparison <: Test
  data::Tuple
  expected
end

struct TestSet <: Test
  name::String
  tests::Vector{Test}
end

const current_testset = Ref{Union{Nothing,TestSet}}(nothing)

macro test(x)
  r = if Meta.isexpr(x, :call, 3) && x.args[1] == :(==)
    :(Comparison(@timed($(esc(x.args[2]))), $(esc(x.args[3]))))
  else
    :(Result(@timed $(esc(x))))
  end
  :(handle($r))
end

testset(fn, name) = begin
  ts = handle(TestSet(name, []))
  @dynamic! let current_testset = ts; fn() end
  ts
end

handle(t::Test) = begin
  ts = current_testset[]
  isnothing(ts) || push!(ts.tests, t)
  t
end

@eval macro $(:catch)(expr)
  quote
    (function()
      try $(esc(expr)) catch e return e end
      error("did not throw an error")
    end)()
  end
end

doodle(r::Test) = begin
  time, bytes, gctime, mallocs = data(r)
  pass = ispass(r)
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
    [:span pass ? pass_icon(r) : fail_icon(r)]
    [:span round(Int, 1000time) [:span "ms"] " $(mallocs)mallocs " replace(datasize(bytes), ' '=>"")]]
end

doodle(c::Comparison) = begin
  a, time, bytes, gctime, memallocs = c.data
  ispass(c) && return doodle(Result((true, time, bytes, gctime, memallocs)))
  notify_fail()
  @dom[hstack "💥" doodle(deepdiff(a, c.expected))]
end

data(t::Test) = [t.data[2:4]..., t.data[5].poolalloc]
data(t::TestSet) = map(+, map(data, t.tests)...)
ispass(t::Result) = t.data[1]
ispass(t::Comparison) = t.data[1] == t.expected
ispass(t::TestSet) = all(ispass, t.tests)
fail_icon(::Test) = "✗"
pass_icon(::Test) = "✓"
pass_icon(::TestSet) = "👍"
fail_icon(::TestSet) = "👎"

showdiff(io, diff) = show(IOContext(io, :color=>true), diff)
doodle(d::DeepDiff) = @dom[:span color(sprint(showdiff, d))]
doodle(d::SimpleDiff) = @dom[:span "got " doodle(d.before) " expected " doodle(d.after)]

notify_fail(d=current_device()) = msg("test failed", convert(NamedTuple, d.snippet))
notify_pass(d=current_device()) = msg("test passed", convert(NamedTuple, d.snippet))
