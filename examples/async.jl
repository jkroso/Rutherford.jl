#! ../bin/rutherford
#
# Demonstrates how asynchronously generated content can be displayed.
# This enables you to generate complex content without locking up the UI
# from further interactions
#
@use "github.com/jkroso/Rutherford.jl" doodle @dom @css_str ["stdlib/TextField.jl" TextField]
@use "github.com/jkroso/Promises.jl" @thread

struct AppState
  value
end

doodle(s::AppState) = begin
  @dom[:div css"""
            width: 500px
            display: flex
            align-items: center
            flex-direction: column
            padding: 10px 0
            """
    [TextField css"""
               width: 100%
               padding: 10px
               border-radius: 3px
               border: 1px solid grey
               font-size: 16px
               """
               focus=true
               key=:value]
    @thread begin
      sleep(1) # some time consuming computation
      @dom[:div css"""
                padding: 10px
                color: rgb(150,150,150)
                letter-spacing: .09em
                """
        s.value]
    end]
end

AppState("")
