##
# Demonstrates how asynchronously generated content can be displayed.
# This enables you to generate complex content without locking up the UI
# from further interactions
#
@require "github.com/jkroso/DOM.jl" HTML @dom @css_str
@require "github.com/jkroso/Promises.jl" @thread
@require "../stdlib" TextFeild scope
@require ".." App window

main(data) =
  @dom [HTML css"""
             display: flex
             align-items: center
             flex-direction: column
             padding-top: 100px
             """
    [:div css"width: 500px"
      [scope(TextFeild, :input) css"""
                                width: 100%
                                padding: 10px
                                border-radius: 3px
                                border: 1px solid grey
                                font-size: 16px
                                """]
      @thread begin
        sleep(1) # some time consuming computation
        @dom [:div css"""
                   padding: 10px
                   color: rgb(150,150,150)
                   letter-spacing: .09em
                   """
          data[:input][:value]]
      end]]

const app = App("Async Example", version=v"1.7.10")
const data = Dict(:input => Dict(:value=>"", :focused=>true))
const w = window(main, app, data)
wait(w) # keeps the process open
