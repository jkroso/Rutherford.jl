##
# Demonstrates how asynchronously generated content can be displayed.
# This enables you to generate complex content without locking up the UI
# from further interactions
#
@require "github.com/jkroso/Rutherford.jl/stdlib" TextFeild scope
@require "github.com/jkroso/DOM.jl" HTML @dom @css_str
@require "github.com/jkroso/Rutherford.jl" async UI

const pending = @dom [:div "Sleeping..."]

UI(Dict(:input=>Dict(:value=>"", :focused=>true))) do data
  @dom [:div css"""
             width: 500px
             display: flex
             align-items: center
             flex-direction: column
             padding: 10px 0
             """
    [scope(TextFeild, :input) css"""
                              width: 100%
                              padding: 10px
                              border-radius: 3px
                              border: 1px solid grey
                              font-size: 16px
                              """]
    async(pending) do
      sleep(1) # some time consuming computation
      @dom [:div css"""
                 padding: 10px
                 color: rgb(150,150,150)
                 letter-spacing: .09em
                 """
        data[:input][:value]]
    end]
end
