@use "github.com/jkroso/Prospects.jl" interleave
@use "github.com/jkroso/DOM.jl" @css_str @dom

const home = @dom[:svg viewBox="0 0 20 20" ariaHidden="true" css"min-width: 1em; display: block; fill: currentColor; stroke: currentColor;"
  [:path d="M9.293 2.293a1 1 0 011.414 0l7 7A1 1 0 0117 11h-1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-3a1 1 0 00-1-1H9a1 1 0 00-1 1v3a1 1 0 01-1 1H5a1 1 0 01-1-1v-6H3a1 1 0 01-.707-1.707l7-7z"]]

const arrow = @dom[:svg css"min-width: 1em; height: 100%; display: block; stroke: currentColor; stroke-width: 1" ariaHidden="true" preserveAspectRatio="none" fill="none" viewBox="0 0 24 44"
  [:path d="M.293 0l22 22-22 22"]]

function breadcrumb(attrs, children)
  @dom[:nav css"""
            display: flex
            padding: 0 1em 0 0
            color: rgb(55 65 81)
            border: 1px solid #e5e7eb
            border-radius: 0.385em
            background: white
            height: 2.8em
            svg {margin: 0 1em; stroke: #e5e7eb; height: 100%}
            svg:first-child {height: 1em; stroke: rgb(55 65 81)}
            """
    [:ol css"display: inline-flex; align-items: center; padding: 0; margin: 0; height: 100%;"
      home interleave(children, arrow)...]]
end

@dom[breadcrumb "Home" "Desktop" "Project"]
