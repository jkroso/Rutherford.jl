##
# Demonstrates how asynchronously generated content can be displayed.
# This enables you to generate complex content without locking up the UI
# from further interactions
#
@require "github.com/jkroso/Cursor.jl" Cursor need
@require "github.com/jkroso/DOM.jl" Container HTML @dom @css_str
@require "github.com/jkroso/Promises.jl" @thread
@require "../stdlib" TextFeild
@require ".." App Window

Base.convert(::Type{Container{:html}}, c::Cursor) = begin
  @dom [HTML css"""
             display: flex
             align-items: center
             flex-direction: column
             padding-top: 100px
             """
    [:div css"width: 500px"
      [TextFeild cursor=c[:input] css"""
                                  width: 100%
                                  padding: 10px
                                  border-radius: 3px
                                  border: 1px solid grey
                                  font-size: 16px
                                  """]
      @thread begin
        sleep(1) # some time consuming computation
        @dom [:div need(c)[:input][:value]]
      end]]
end

const app = App("Async Example", version=v"1.7.6")
const data = Dict(:input => Dict(:value=>"", :focused=>true))
const window = Window(app, data)
wait(window) # keeps the process open
