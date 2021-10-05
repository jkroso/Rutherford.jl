# Redesign

Julia is the first language to implement a really good generic programming system. Rutherford.jl aims to extend this capability into UI programming where there are a couple complications.

Firstly, UIs mutate the data that they depend on. With a normal function if your data isn't in the right format you will just convert it and move on. But with UIs you also need to convert the mutations. And since those mutations are generated dynamically and asynchronously that's not so easy to do.

Secondly, UI's have opinions. Normally functions are computing something that is well defined and either right or wrong. But UI's aren't that. For any given data there are many sensible UIs that could be generated for it and the difference between them can be as trivial as a colour change.

Ultimately what these two things mean is that as the author of a generic UI you need to assume the following:

- You don't know how to access the data you are presenting
- You don't know how to mutate the data
- You don't know what the end user wants the UI to look like

At this point you might think writing generic UIs is a fools errand. But it's not. There is still a lot that you can do. Firstly you can define the structure of the UI. You can define the interactions that users can perform and it and you can describe the mutations that will result from those interactions. And you can even provide sensible defaults for all the end user specific stuff like how to access data, how things should look, and how the mutations should be interpreted. Which will ultimately mean that the end user can plonk your UI component into their's and then gradually specialise certain functions until it works.

## Solution

Rutherford.jl is a retained mode system. You initialize your UI then mutate it according to input from outside sources such as the user, database, and network. This is in contrast to contemporarily popular systems like React.js which try to provide the API of an immediate mode system with the efficiency of a retained mode system. React proves you can go a long way with this approach. But some UI's are conceptually stateful systems and it gets awkward when dealing with them. For example, animations and keyboard focus are hard to do describe in React.js. Basically my view is that it's much easier to add immediate mode parts to a retained mode system than to add retained mode parts to an immediate mode system. So Rutherford.jl is a retained mode system with immediate modes parts where possible.

## API

In Rutherford.jl UI's are represented as a graph with each node being a subtype of `UINode`.

```julia
abstract type UINode
  parent::Union{Nothing, UINode}
  previous_sibling::Union{Nothing, UINode}
  next_sibling::Union{Nothing, UINode}
  first_child::Union{Nothing, UINode}
end
```

### `createUI(data::Any)::UINode`

Takes some data and generates a user interface for viewing and manipulating it

### `tick(::UINode)`

Tells the UI that time has passed. If components need to mutate themselves as
time passes they can specialize this function

### `emit(::UINode, ::Event)`

This is invoked when the user interacts with the `UINode`. Usually either a mouse event or a keystroke.

### `focus(c::UINode)`

Switch keyboard focus to `c` so that future keystrokes will be directed towards it via `emit(c, event)`.
