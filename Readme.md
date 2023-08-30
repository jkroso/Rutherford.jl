# Redesign

In Rutherford UI's are represented as a mutable tree data structure (technically a graph because children carry references to their parent). To create an App you load your state from a database of some sort then generate an initial UI from that. From then on you respond to events by mutating this UI representation and the underlying data. When this UI structure is mutated it gets re-rendered to the users screen. The code for doing this should be written in a declarative manner for simplicity sake with the rendering engine responsible for making the necessary performance optimisations.

## API

In Rutherford.jl UI's are represented as a graph with each node being a subtype of `UINode`.

```julia
abstract type UINode
  state::Any
  parent::Union{Nothing, UINode}
  previous_sibling::Union{Nothing, UINode}
  next_sibling::Union{Nothing, UINode}
  first_child::Union{Nothing, UINode}
end

@UI Dictionary(isopen=false)
UI(d::Dict) = begin
  @UI[Dictionary
    (@UI[Row [Key k] [Value v]] for (k,v) in d)...]
end
render(::Type{DOM}, d::Dictionary) = begin
  @dom[vstack
    [hstack arrow(d.state.isopen) brief(d)]
    if d.state.isopen
      details(d)
    end]
end
onclick(d::Dictionary, e) = d.state.isopen = !d.state.isopen
UI(Dict(:a=>1,:b=>2))
```

### `UI(data::Any)::UINode`

Takes some data and generates a user interface for viewing and manipulating it

### `tick(::UINode)`

Tells the UI that time has passed. If components need to mutate themselves as
time passes they can specialise this function

### `emit(::UINode, ::Event)`

This is invoked when the user interacts with the `UINode`. Usually either a mouse event or a keystroke.

### `focus(c::UINode)`

Switch keyboard focus to `c` so that future keystrokes will be directed towards it via `emit(c, event)`.

### `render(::Type{DOM}, ::UINode)`

Generates a HTML DOM representation of the UINode that can be displayed on screen by any HTML rendering engine

## Juno

Juno integration is just a matter of loading one file on the Atom side and one on the Julia side.

Add this to your `~/.atom/init.coffee`

```js
require process.env.HOME + "/.kip/repos/jkroso/Rutherford.jl/juno.js"
```

Add This to your `~/.julia/config/startup.jl`

```julia
eval(:(isinteractive() && @use "github.com/jkroso/Rutherford.jl/draw.jl"))
```

And you will probably want to add some keyboard shortcuts to your `~/.atom/keymap.cson`

```coffee
'.platform-darwin .item-views > atom-text-editor[data-grammar="source julia"]:not([mini])':
  'cmd-ctrl-enter': 'julia-client:eval-block'
  'cmd-alt-ctrl-enter': 'julia-client:eval-each'
  'cmd-ctrl-backspace': 'julia-client:reset-module'
```
