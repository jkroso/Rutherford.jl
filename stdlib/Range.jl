@use "github.com/jkroso/DOM.jl" @css_str @dom

function slider(atrrs, children)
  @dom[:div css"""
            margin: 1rem
            input
              -webkit-appearance: none
              cursor: pointer
              width: 20rem
              height: 1rem
              border-radius: 1rem
              background: white
            input::-webkit-slider-container
              border: 1px solid #e5e7eb
              border-radius: 1rem
            input::-webkit-slider-runnable-track
              -webkit-appearance: none
              background-image: linear-gradient(black, black)
              background-size: 50% 100%
              background-repeat: no-repeat
              height: 1.5rem
              border-radius: 1rem
              display: flex
            input::-webkit-slider-thumb
              -webkit-appearance: none
              display: block
              align-self: center
              height: 1.5rem
              width: 1.5rem
              border-radius: 50%
              background: white
              border: 1px solid black
              cursor: ew-resize
              box-shadow: 0 0 3px 0 #555
              transition: background .3s ease-in-out
            """
    [:input type="range" value="50" min="0" max="100"]]
end

@dom[slider]
