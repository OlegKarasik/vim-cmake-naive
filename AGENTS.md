# Core Rules

1. This is an independent plugin. Never introduce dependencies for other
   plugins.
2. All work must be done in boundries of the repository directory. Never create
   scripts or files outside of repository directory.
3. All errors and warnings must be issues throught the Vim build-in errors and
   warnings functionality.

# Popup Rules

1. All popups with titles have smooth, single line borders (as modern Vim popups).
2. All popups with titles have standard Vim popup colours for background and
   selection.
3. All popups with titles DO NOT have ':' at the end.
4. All popups with titles (which is used for selecting items) have FIXED width of
   30 symbols.
5. All popups with titles (which is used for selecting items) have DYNAMIC height
   to keep up to 10 lines. If there are more than 10 lines, the popup scaled to 10
   lines and supports scrolling.
6. All popups with titles (which is used for selecting items) have numbers in
   front of every item and display current item with * symbol, which is placed
   between the number and item.

# Debug Rules

1. All debug operations MUST be scoped to repository directory. Never create or
   edit a file outside of repository directory.

# Asynchronous Rules

1. All long running operations (invocation of external tools) must be
   asynchronous.
2. All asynchronous operations use vim terminal feature.
