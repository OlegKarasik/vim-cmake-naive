# Additional Public Vimscript Functions (No Ex command wrapper)

**Scope:** Public API functions without Ex command wrappers.
**Trigger keywords:** vim_cmake_naive#, split API, switch API, startup sync API.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

## `vim_cmake_naive#split(<build-directory>, [...options])`

1. Splits a root `compile_commands.json` into target-local files.
2. Supports:
   1. `-i`, `--input`, `--input=<path>`
   2. `-o`, `--output-name`, `--output-name=<name>`
   3. `--dry-run`
3. Output file name must be a file name only (no path separators).

## `vim_cmake_naive#switch(<build-directory>, <target>, [...options])`

1. Copies target-local `compile_commands.json` into active output location.
2. Supports output override:
   1. `-o <path>`
   2. `--output <path>`
   3. `--output=<path>`

## `vim_cmake_naive#set_config_preset(<preset>)`

1. Requires local configuration to exist.
2. Validates that `<preset>` is non-empty.
3. Resolves local configuration in current directory or parent directories.
4. Sets `preset` to the exact provided string.
5. Updates local `.vimspector` integration variable values when those variable
   definitions already exist.

## `vim_cmake_naive#set_config_build_config(<build>)`

1. Requires local configuration to exist.
2. Validates that `<build>` is non-empty.
3. Resolves local configuration in current directory or parent directories.
4. Sets `build` to the exact provided string.
5. Updates local `.vimspector` integration variable values when those variable
   definitions already exist.

## `vim_cmake_naive#sync_startup_integration_files()`

1. Resolves Root Directory from current working directory.
2. Resolves nearest existing Local Configuration under that root.
3. Reads `target` and resolved Build Directory from config.
4. Writes those values into local `.vimspector` `variables` blocks
   (top-level or nested, for example `configurations.<name>.variables`) for
   `VIM_CMAKE_NAIVE_TARGET` and `VIM_CMAKE_NAIVE_OUTPUT`.
5. If root/config is missing, startup-style call is treated as no-op.

## `vim_cmake_naive#register_plug_mappings()`

1. Registers `<Plug>(...)` mappings for all public commands.
2. Does not override existing mappings with the same left-hand side.
3. Registers `<Plug>(CMakeConfigSetOutput)` with a trailing space for argument
   entry.
