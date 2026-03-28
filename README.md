# vim-cmake-naive

> [!WARNING]
> This plugin was written by AI, except for `AGENTS.md`.

`vim-cmake-naive` is a Vim plugin for working with CMake `compile_commands.json` files.

It provides eleven commands:

- `:CMakeConfig`
- `:CMakeConfigDefault`
- `:CMakeSwitchPreset`
- `:CMakeSwitchTarget`
- `:CMakeGenerate`
- `:CMakeBuild`
- `:CMakeConfigSetPreset <preset>`
- `:CMakeResetPreset`
- `:CMakeResetTarget`
- `:CMakeConfigSetBuild <value>`
- `:CMakeConfigSetOutput <value>`

## Install (vim-plug)

```vim
Plug 'YOUR_GITHUB_USER/vim-cmake-naive'
```

Then run:

```vim
:PlugInstall
```

## Usage

Create local CMake config file for this project:

```vim
:CMakeConfig
```

This creates `.vim/.cmake/.config.json` in the nearest ancestor directory that
contains `CMakeLists.txt` (searching from current directory upward). If no
`CMakeLists.txt` is found, the command reports an error.

Apply default local CMake configuration:

```vim
:CMakeConfigDefault
```

This creates/updates `.vim/.cmake/.config.json` in the nearest ancestor
directory that contains `CMakeLists.txt` (searching upward from current
directory), with:
- `output`: `"build"`
- `preset`: `""`
- `build`: `"Debug"`

If no `CMakeLists.txt` is found, the command reports an error.

Generate CMake build system from local config:

```vim
:CMakeGenerate
```

This command:
- finds nearest `CMakeLists.txt` from current directory upward
- finds nearest existing `.vim/.cmake/.config.json`, or creates default config
  at the discovered CMake project root when none exists
- runs `cmake` with config values:
  - `output` -> `-B <build-dir>`
  - `build` -> `-DCMAKE_BUILD_TYPE=<build>`
  - `preset` -> `--preset <preset>` (when non-empty)

Build project with CMake from local config:

```vim
:CMakeBuild
```

This command:
- finds nearest `CMakeLists.txt` from current directory upward
- finds nearest existing `.vim/.cmake/.config.json`, or creates default config
  at the discovered CMake project root when none exists
- runs `cmake --build <output>`
- adds `--preset <preset>` when config `preset` is non-empty
- adds `--target <target>` when config `target` is non-empty

Switch local CMake preset from `CMakePresets.json`:

```vim
:CMakeSwitchPreset
```

This command:
- finds nearest `CMakeLists.txt` from current directory upward
- reads `CMakePresets.json` at that project root
- lists selectable configure presets (non-hidden, condition evaluates to true) in sorted order
- prompts through a popup menu for selection (fallback to menu/inputlist) and applies it via `:CMakeConfigSetPreset`
- popup entries are ordered and prefixed with a number
- currently selected preset is marked with `*`

If `CMakePresets.json` is missing, the command reports an error.

Switch local CMake target from discovered target folders:

```vim
:CMakeSwitchTarget
```

This command:
- reads nearest existing `.vim/.cmake/.config.json`
- resolves build directory from config `output` (relative to config root)
- uses config `preset` to scan `<output>/<preset>` when that directory exists, otherwise falls back to `<output>`
- discovers target directories in `**/CMakeFiles/*.dir`
- prompts through a popup menu for selection (fallback to inputlist) and writes selected target to config key `target`
- popup entries are ordered and prefixed with a number
- currently selected target is marked with `*`
- popup shows at most 5 targets at once and supports scrolling for longer lists
- copies selected target `compile_commands.json` to `<output>/compile_commands.json`
- if selected target file is missing, splits root `compile_commands.json` (found at `<output>/<preset>` or `<output>`) and retries copy

Set the local CMake preset in `.vim/.cmake/.config.json`:

```vim
:CMakeConfigSetPreset debug
:CMakeConfigSetPreset Release With DebInfo
```

This updates the nearest existing `.vim/.cmake/.config.json` in current
directory or parent directories. If no local config exists, the command reports
an error (run `:CMakeConfig` or `:CMakeConfigDefault` first).

Reset the local CMake preset to empty:

```vim
:CMakeResetPreset
```

This creates the config file if needed and sets the `preset` key to `""`.

Reset the local CMake target to empty:

```vim
:CMakeResetTarget
```

This creates the config file if needed and sets the `target` key to `""`.

Set local CMake build config in `.vim/.cmake/.config.json`:

```vim
:CMakeConfigSetBuild Debug
:CMakeConfigSetBuild RelWithDebInfo
```

This updates the nearest existing `.vim/.cmake/.config.json` in current
directory or parent directories. If no local config exists, the command reports
an error (run `:CMakeConfig` or `:CMakeConfigDefault` first).

Set local CMake output in `.vim/.cmake/.config.json`:

```vim
:CMakeConfigSetOutput build
:CMakeConfigSetOutput out/build
```

This updates the nearest existing `.vim/.cmake/.config.json` in current
directory or parent directories. If no local config exists, the command reports
an error (run `:CMakeConfig` or `:CMakeConfigDefault` first).

## Notes

- Errors are reported through Vim messages with a `[vim-cmake-naive]` prefix.
