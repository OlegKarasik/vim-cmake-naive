# Concepts

**Scope:** Shared definitions and cross-command behavior.
**Trigger keywords:** root directory, local configuration, local cache, build directory, compile commands, command lock.
**Depends on:** `agents/core/rules.md`.
**Conflicts:** none.

## Root Directory

The nearest ancestor directory (from current working directory upward) that
contains `CMakeLists.txt`. Many commands fail immediately if this directory cannot
be found.

## Local Configuration

`.vim-cmake-naive-config.json` file at the Root Directory.

Keys:

1. `output` - build output root (default fallback: `build`)
2. `preset` - CMake preset name (empty string means "no preset")
3. `build` - CMake build type (default fallback: `Debug`)
4. `target` - active selected target (missing means `all`)

## Local Cache

`.vim-cmake-naive-cache.json` file at the Root Directory.

Keys:

1. `targets` - list of discovered target names

## Build Directory

Resolved from Local Configuration:

1. If `preset` is empty: `<root>/<output>`
2. If `preset` is set: `<root>/<output>/<preset>`

## Integration State Files

These files are maintained in the Root Directory:

1. `.vim-cmake-naive-target` - current target name (is empty when target key is
   missing)
2. `.vim-cmake-naive-output` - current build directory path relative to root
   (`<output>` or `<output>/<preset>`)

They are updated whenever local configuration is written.

When `g:vim_cmake_naive_sync_makeprg` is enabled, config writes also sync global
`makeprg` to the same `cmake --build ...` command used by `:CMakeBuild` (useful
for tools that read `&makeprg`). If `g:vim_cmake_naive_make_errorformat` is
set, config sync also writes that value to global `errorformat`.

## Startup

During startup, the plugin:

1. Reads `target` and the resolved Build Directory from Local Configuration.
2. Saves those values into the Integration State Files
   (`.vim-cmake-naive-target` and `.vim-cmake-naive-output`).

## Active and Target Compile Commands

1. Active file: `<output>/compile_commands.json` (used as the main compile
   database)
2. Target-local files:
   `<build-directory>/**/CMakeFiles/<target>.dir/compile_commands.json`

## Command Lock

All public `:CMake*` commands run through a single lock. If one command is
already running, a new command is rejected with:
`CMake: another command <CommandName> is already running`.

## Terminal Reuse

The following commands are run asynchronously and share the same Vim terminal
backend:

1. `CMakeBuild`
2. `CMakeTest`
3. `CMakeRun`
4. `CMakeGenerate`

By default, these commands do not open preview windows automatically. They run in
hidden terminal buffers and report progress/start and final operation result via
messages (including percentage progress lines with terminal title text).

If a plugin CMake preview window is already visible, these commands reuse that
preview window and stream their new terminal output there.

Use `CMakeShowPreview` to show the most recent hidden terminal output in a preview
window, and `CMakeHidePreview` to hide preview windows without wiping those
terminal buffers.
