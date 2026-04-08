# Core Rules

1. This is an independent plugin. Never introduce dependencies for other
   plugins.
2. All work must be done in boundries of the repository directory. Never create
   scripts or files outside of repository directory.
3. All errors and warnings must be issues throught the Vim build-in errors and
   warnings functionality.
4. The plugin must be compatible with `vim-plug` and keep a standard Vim plugin
   layout (`plugin/` and `autoload/`).

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
7. All popups which support search must enter/exit search mode using "CTRL+I"
   hotkey. Search in the popup items must be performed after input of every
   character. Inside the insert mode, popup title is updated to have "(Insert)" at
   the end.
8. All popups which support selection should respond to "x" and "ESC" to close the
   popup, "j" and "DOWN" to move down, "k" and "UP" to move up, "b" and "ENTER" to
   make a choice.

# Debug Rules

1. All operations MUST be scoped to repository directory. Never create or
   edit a file outside of repository directory.
2. Information about vim commands and functions must be retrieved using the
   `:help` command inside the vim. 

# Asynchronous Rules

1. All long running operations (invocation of external tools) must be
   asynchronous.
2. All asynchronous operations use vim terminal feature.

# Concepts

1. "Root Directory" - a directory where `CMakeLists.txt` file is located. "Root
   Directory" is detected at runtime by searching for `CMakeLists.txt` upward
   starting from the current directory.
2. "Local Configuration" - a configuration file (`.vim-cmake-naive-config.json`)
   located in the root directory.
2. "Local Cache" - a cache file (`.vim-cmake-naive-cache.json`) located in the
   root directory. 
3. "Build Directory" - an directory path which is composed from root directory
   path + `<output>/<preset>` values from local configuration if there is a
   `<preset>` value set. Otherwise, it is set to root directory path + `<output>`.
