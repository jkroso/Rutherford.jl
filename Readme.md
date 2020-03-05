# Rutherford.jl: Generic UI Programming

Julia is the first language to implement a really good generic programming system. Rutherford.jl aims to extend this capability into UI programming where there are a couple complications.

Firstly, UIs mutate the data that they depend on. With a normal function if your data isn't in the right format you will just convert it and move on. But with UIs you also need to convert the mutations. And since those mutations are generated dynamically and asynchronously that's not so easy to do.

Secondly, UI's have opinions. Normally functions are computing something that is well defined and either right or wrong. But UI's aren't that. For any given data there are many sensible UIs that could be generated for it and the difference between them can be as trivial as a colour change.

Ultimately what these two things mean is that as the author of a generic UI you need to assume that you don't know how to access the data you are presenting, you don't know how to mutate it, and you don't even know exactly what the end user wants the UI to look like. At this point you might think writing generic UIs is a fools errand. But it's not. There is still a lot that you can do. Firstly you can define the structure of the UI. You can define the interactions that users can perform and it and you can describe the mutations that will result. And you can even provide sensible defaults for all the end user specific stuff like how to access data, how things should look, and how the mutations should be interpreted. Which will ultimately mean that the end user can plonk your UI component into their's and then gradually specialise certain functions until it works.

The solution to all this is surprisingly simple. UIs can naturally be described using a tree data structure. So making the behaviour of this tree generic is just a matter of using custom types to uniquely tag each part of the tree that we think the end user might want to specialise. With this in mind we can now take a look at the API.

## API

1. `@component(name::Symbol)` This creates a type that can be used in a UI tree and will enable end users to specialise the rest of Rutherford.jl's API on them
2. `draw([::Context,] data)` As the user of someone else's component or datatype, you can override the default rendering by defining a draw method for the context you are using it in.
3. `doodle([::Component,] data)` If you are creating a Component you should define the 2 argument version. If you a creating a DataType you should define the single argument version
4. `data(::Context)` This is where the `data` parameter for `draw` is generated. In here you should get the data that will be presented by a component and convert it into the format the component is expecting

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
