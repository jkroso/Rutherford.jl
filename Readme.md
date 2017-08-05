# Rutherford

A UI toolkit based on [Electron](//github.com/atom/electron)

## Top Level Design

<img src="Static UI.png" align="right" width="280" title="Static UI"/>

The simplest UI just takes some data and creates a static visualization of it. One example is `ls(1)` which presents a list of files in a given directory. It can be implemented with a simple function in almost any language. But it falls short when the the list of files is too long to fit on the users screen at one time. Solving this requires you to keep track of scroll state which necessarily makes the UI's architecture more complicated. What was a simple function now needs to be able to modify its input. Creating a cyclic relationship between the UI and the data it presents.
<img src="Interactive UI.png" align="right" width="280" title="Interactive UI"/>

Rutherford enables you to implement this architecture by rendering your UI using a single function that takes one large data graph as input. Your UI will expose event listeners that will be invoked as the user interacts with the UI. These listeners will then modify the data graph and the rendering function will be run again on the updated data to produce a whole new UI. The difference between the two UI's will then be computed by Rutherford and it will apply a patch to change what's rendered on the screen to match what the new UI asks for. Therefore, as a developer using Rutherford, you write code that desribes how a given set of data should be rendered. And Code which describes how user interactions affect the data. This is as simple as it can be.

[Escher.jl](http://escher-jl.org) is similar but with it you render a static UI then wire up the interactive UI architecture described here in just the bits that are actually interactive. This is likely to perform better but requires you to break up your data into little chunks designed for each little interactive section of your UI. Then you have to reassemble those chunks when you want to persist the data back into your database. So it's extra work. Rutherford can be thought of as Escher.jl were you only allowed one Signal.
