# Core Rules

1. This is an independent plugin. Never introduce dependencies for other plugins.
2. All work must be done in boundries of the repository directory. Never create
   scripts or files outside of repository directory. Never redirect output outside
   of repository.
3. All errors and warnings must be issues throught the Vim build-in errors and
   warnings functionality.
4. The plugin must be compatible with `vim-plug` and keep a standard Vim plugin
   layout (`plugin/` and `autoload/`).
5. All public executable commands must support `<Plug>(<command>)` syntax to
   enable keybindings by default.
6. All plugin files/internal function should be named after the plugin, for
   instance if plugin name is `vim-buffers-naive`, then all related files should
   be `vim_buffers_naive*`.

# Core Popup Rules

1. All popups with titles have smooth, single line borders (as modern Vim popups).
2. All popups with titles have standard Vim popup colours for background and
   selection.
3. All popups with titles DO NOT have ':' at the end.
4. All popups with titles have MAX width of 30 symbols and MIN width of 10
   symbols.
5. All popups which respond to "x" and "ESC" to close the popup, "j" and "DOWN" to
   move down, "k" and "UP" to move up, "b" and "ENTER" to make a choice.

## Popup with Selection

1. All popups with titles which are used for selecting items have DYNAMIC height
   to keep up to 10 lines. If there are more than 10 lines, the popup scaled to 10
   lines and supports scrolling.
2. All popups with titles which are used for selecting items have numbers in front
   of every item and display current item with * symbol, which is placed between
   the number and item.
3. All popups with titles which are used to selecting items support search must
   enter/exit search mode using "CTRL+I" hotkey. Search in the popup items must be
   performed after input of every character. Inside the insert mode, popup title
   is updated to have "(Insert)" at the end. Exiting search mode retains input
   filter. Also, in search mode popup support `CTRL+U` (to clear the filter).

## Popup Menus

1. All popups with titles which are used for menus (for instance, command
   invocation) and do no require to restore state on repeating execution MUST to
   no an indicator of the current item `*`.

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
