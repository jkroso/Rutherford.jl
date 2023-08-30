function button(attrs, children)
  @dom[:button{style"""
               pad(4 2)
               text(small medium gray)
               background(white)
               border(gray top bottom)
               onhover {background(gray) text(blue)}
               onfocus {z(10) ring(2 blue) text(blue)}
               """, attrs...} children...]
end

function button_group(attrs, children)
  @dom[hbox style"radius(medium) shadow"
    [button style"border(left) radius(large left)" "Profile"]
    [button "Settings"]
    [button style"border(right) radius(large right)" "Messages"]]
end
