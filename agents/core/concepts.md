# Concepts

**Scope:** Shared definitions and cross-command behavior.
**Trigger keywords:** root directory, local configuration, local cache, build directory, compile commands, command lock.
**Depends on:** `agents/core/rules.md`.
**Conflicts:** none.

## Root Directory

The nearest ancestor directory that contains `CMakeLists.txt`. Resolution starts
from current working directory upward; if no root is found and current buffer
has a file path, resolution retries from that file path upward. Many commands
fail immediately if this directory cannot be found.

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

## Vimspector Integration Variables

When local `.vimspector.json` exists at the Root Directory and has `variables`
blocks (top-level or nested, for example `configurations.<name>.variables`),
these values are updated:

1. `VIM_CMAKE_NAIVE_TARGET` - current target name (is empty when target key is
   missing)
2. `VIM_CMAKE_NAIVE_OUTPUT` - current build directory path relative to root
   (`<output>` or `<output>/<preset>`)

Missing `.vimspector.json` file or missing variable definitions are treated as no-op.

When `g:vim_cmake_naive_sync_makeprg` is enabled, config writes also sync global
`makeprg` to the same `cmake --build ...` command used by `:CMakeBuild` (useful
for tools that read `&makeprg`). If `g:vim_cmake_naive_make_errorformat` is
set, config sync also writes that value to global `errorformat`.

## Startup

During startup, the plugin:

1. Reads `target` and the resolved Build Directory from Local Configuration.
2. Saves those values into local `.vimspector.json` variable definitions
   (`VIM_CMAKE_NAIVE_TARGET` and `VIM_CMAKE_NAIVE_OUTPUT`) when present.

## Active and Target Compile Commands

1. Active file: `<output>/compile_commands.json` (used as the main compile
   database)
2. Target-local files:
   `<build-directory>/**/CMakeFiles/<target>.dir/compile_commands.json`

## Command Lock

All public `:CMake*` commands except `CMakeShowPreview`, `CMakeHidePreview`,
and `CMakeCancel` run through a single lock. If one command is already running,
a new command is rejected with:
`CMake: another command <CommandName> is already running`.

`CMakeShowPreview` and `CMakeHidePreview` are allowed while a terminal command
is running so preview visibility can be managed without waiting for completion.
`CMakeCancel` is also allowed so the active terminal job can be terminated.

## Terminal Reuse

The following commands are run asynchronously and share the same Vim terminal
backend:

1. `CMakeBuild`
2. `CMakeTest`
3. `CMakeRun`
4. `CMakeGenerate`

By default, these commands do not open preview windows automatically. They run in
hidden terminal buffers and update global statusline with command label and
elapsed runtime while running. On completion, statusline is restored to its
pre-command value, and completion is reported in Vim messages with `[Success]`
or `[Error]` suffix.

If a plugin CMake preview window is already visible, these commands reuse that
preview window and stream their new terminal output there.

Use `CMakeShowPreview` to show the most recent hidden terminal output in a preview
window, and `CMakeHidePreview` to hide preview windows without wiping those
terminal buffers.
