@use ".." draw @dom @css_str @component

@component StackItem
@component VStack
draw(c::VStack, data) =
  @dom[:div{c.attrs...} css"display: flex; flex-direction: column"
    (@dom[StackItem key=i] for i in 1:length(data))...]
