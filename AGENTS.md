# Core Rules

1. This is an independent plugin. Never introduce dependencies for other
   plugins.
2. All work must be done in boundries of the repository directory. Never create
   scripts or files outside of repository directory.

# Popup Rules

1. All popups with titles have smooth, single line borders (as modern Vim popups).
2. All popups with titles have standard Vim popup colours for background and
   selection.
3. All popups with titles DO NOT have ':' at the end.
4. All popups with titles (which is used for selecting items) have FIXED width of
   30 symbols.
5. All popups with titles (which is used for selecting items) have FIXED height to
   keep 7 lines. If there are more than 7 lines, the popup supports scrolling.
6. All popups with titles (which is used for selecting items) have numbers in
   front of every item and display current item with * symbol, which is placed
   between the number and item.
