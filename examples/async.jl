#! ../bin/rutherford
#
# Demonstrates how asynchronously generated content can be displayed.
# This enables you to generate complex content without locking up the UI
# from further interactions
#
@require "github.com/jkroso/Rutherford.jl/stdlib" TextField default_state
@require "github.com/jkroso/Rutherford.jl" async UI @dom @css_str
@require "github.com/jkroso/Prospects.jl" assoc

UI(nothing) do state
  input = @dom[TextField css"""
                         width: 100%
                         padding: 10px
                         border-radius: 3px
                         border: 1px solid grey
                         font-size: 16px
                         """
                         isfocused=true]
  @dom[:div css"""
            width: 500px
            display: flex
            align-items: center
            flex-direction: column
            padding: 10px 0
            """
    input
    async(@dom[:div "Sleeping..."]) do
      sleep(1) # some time consuming computation
      @dom[:div css"""
                padding: 10px
                color: rgb(150,150,150)
                letter-spacing: .09em
                """
        input.state.value]
    end]
end
