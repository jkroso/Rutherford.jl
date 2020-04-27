@use "github.com/jkroso/Rutherford.jl" msg current_device @dynamic!
@use "github.com/jkroso/Rutherford.jl/draw.jl" doodle @dom @css_str hstack vstack
@use "github.com/ssfrr/DeepDiffs.jl" deepdiff DeepDiff SimpleDiff
@use "github.com/jkroso/DOM.jl/ansi.jl" ansi

datasize(value::Number) = begin
  power = max(1, round(Int, value > 0 ? log10(value) : 3) - 2)
  suffix = ["B", "kB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"][power]
  string(round(Int, 1e3*value / 1e3^power), suffix)
end

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
    [:span pass ? "✓" : "✗"]
    [:span round(Int, 1000time) [:span "ms"] " $(round(Int, mallocs))mallocs " datasize(bytes)]]
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

showdiff(io, diff) = show(IOContext(io, :color=>true), diff)
doodle(d::DeepDiff) = @dom[:span ansi(sprint(showdiff, d))]
doodle(d::SimpleDiff) = @dom[:span "got " doodle(d.before) " expected " doodle(d.after)]

notify_fail(d=current_device()) = msg("test failed", convert(NamedTuple, d.snippet))
notify_pass(d=current_device()) = msg("test passed", convert(NamedTuple, d.snippet))
