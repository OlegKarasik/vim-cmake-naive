# vim-cmake-naive

> [!WARNING]
> This plugin was written by AI, except for `AGENTS.md`.

`vim-cmake-naive` is a Vim plugin for working with CMake `compile_commands.json` files.

It provides thirteen commands:

- `:CMakeConfig`
- `:CMakeConfigDefault`
- `:CMakeSwitchPreset`
- `:CMakeSwitchBuild`
- `:CMakeSwitchTarget`
- `:CMakeGenerate`
- `:CMakeBuild`
- `:CMakeInfo`
- `:CMakeMenu`
- `:CMakeMenuFull`
- `:CMakeConfigSetPreset <preset>`
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
- creates `<output>` directory when missing
- when `preset` is non-empty, also creates `<output>/<preset>` when missing
- runs `cmake` with config values:
  - `output` -> `-B <output>` when preset is empty
  - `output` + `preset` -> `-B <output>/<preset>` when preset is non-empty
  - adds `--fresh` to force clean cache regeneration
  - `build` -> `-DCMAKE_BUILD_TYPE=<build>`
  - `preset` -> `--preset <preset>` (when non-empty)
- opens a vertical split terminal and starts generate there asynchronously
- after successful generate completion, scans root `compile_commands.json` from the active build directory
- extracts discovered targets and stores them to `.vim/.cmake/cache.json` field `targets`
- splits root `compile_commands.json` into target-local `compile_commands.json` files under corresponding target directories
- reuses previously opened visible build/generate output window when possible; otherwise recreates it
- returns immediately; completion/failures are reported in that terminal/messages

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
- opens a vertical split terminal and starts the build there asynchronously
- sets terminal status name while running to:
  - `cmake build --preset=<preset> --target=<target>` when preset and target are set
  - `cmake build --target=all` when target is empty
  - omits `--preset=...` when preset is empty
- renames terminal status name on completion to `Success` or `Failure (<code>)`
- reuses previously opened visible build output window when possible; otherwise recreates it
- returns immediately; build completion and failures are reported in that terminal/messages

Show local CMake configuration in popup table:

```vim
:CMakeInfo
```

This command:
- reads nearest existing `.vim/.cmake/.config.json`
- shows popup with key/value table (`key | value`)
- uses standard popup style (smooth single-line border, `Pmenu` colors)
- if config is missing, shows:
  `No configuration, please use CMakeConfigDefault to get started`

Open a compact popup command menu for common CMake commands:

```vim
:CMakeMenu
```

This command:
- shows a popup with only these commands: `CMakeGenerate`, `CMakeBuild`, `CMakeSwitchPreset`, `CMakeSwitchBuild`, `CMakeSwitchTarget`
- uses the same popup style as other selection popups (fixed width 30, smooth borders, dynamic height up to 10)
- executes the selected command

Open a full popup command menu for all plugin CMake commands:

```vim
:CMakeMenuFull
```

This command:
- shows a popup with all available `CMake*` Ex commands from this plugin
- uses the same popup style as other selection popups (fixed width 30, smooth borders, dynamic height up to 10)
- executes the selected command
- asks for arguments when a selected command requires them (for example `CMakeConfigSetPreset`)

Switch local CMake preset from `CMakePresets.json`:

```vim
:CMakeSwitchPreset
```

This command:
- finds nearest `CMakeLists.txt` from current directory upward
- reads `CMakePresets.json` at that project root
- always includes predefined preset `(none)`
- lists selectable configure presets (non-hidden, condition evaluates to true) in sorted order
- prompts through a popup menu for selection (fallback to menu/inputlist) and applies it via `:CMakeConfigSetPreset`
- when a preset other than `none` is selected, removes `build` key from local config
- when `none` is selected, removes `preset` key from local config
- popup entries are ordered and prefixed with a number
- currently selected preset is marked with `*`
- popup uses smooth single-line borders with standard Vim popup colors
- popup title has no trailing `:`
- popup width is fixed to 30 and height is dynamic up to 10 lines with scrolling

If `CMakePresets.json` is missing, the command reports an error.

Switch local CMake build type:

```vim
:CMakeSwitchBuild
```

This command:
- reads nearest existing `.vim/.cmake/.config.json`
- always lists default build types: `Debug`, `Release`, `RelWithDebInfo`, `MinSizeRel`
- prompts through a popup menu for selection (fallback to menu/inputlist) and applies it via `:CMakeConfigSetBuild`
- removes `preset` key from local config after applying selected build type
- popup entries are ordered and prefixed with a number
- currently selected build type is marked with `*`
- popup uses smooth single-line borders with standard Vim popup colors
- popup title has no trailing `:`
- popup width is fixed to 30 and height is dynamic up to 10 lines with scrolling

Switch local CMake target from cached targets:

```vim
:CMakeSwitchTarget
```

This command:
- reads nearest existing `.vim/.cmake/.config.json`
- reads nearest existing `.vim/.cmake/cache.json`
- requires `cache.json` to contain key `targets` generated by `:CMakeGenerate`
- resolves build directory from config `output` (relative to config root)
- always includes predefined target `(all)`
- discovers selectable targets from cache key `targets`
- prompts through a popup menu for selection (fallback to inputlist) and writes selected target to config key `target`
- when `all` is selected, removes `target` key from local config
- popup supports live search: start typing to filter available targets (`Backspace` removes, `Ctrl-U` clears)
- popup entries are ordered and prefixed with a number
- currently selected target is marked with `*`
- popup uses smooth single-line borders with standard Vim popup colors
- popup title has no trailing `:`
- popup width is fixed to 30 and height is dynamic up to 10 lines with scrolling
- copies selected target `compile_commands.json` to `<output>/compile_commands.json`
- when `all` is selected, copies root `compile_commands.json` to `<output>/compile_commands.json`
- if cache file is missing, command reports:
  `No cache found. Please run CMakeGenerate command first.`

Set the local CMake preset in `.vim/.cmake/.config.json`:

```vim
:CMakeConfigSetPreset debug
:CMakeConfigSetPreset Release With DebInfo
```

This updates the nearest existing `.vim/.cmake/.config.json` in current
directory or parent directories. If no local config exists, the command reports
an error (run `:CMakeConfig` or `:CMakeConfigDefault` first).

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
- All `:CMake*` commands use a shared lock. If another `:CMake*` command is in
  progress, command start is rejected with:
  `CMake: another command <command> is already running`.
