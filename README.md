# vim-cmake-naive

> [!WARNING]
> This plugin was written by AI, except for `AGENTS.md`.

`vim-cmake-naive` is a Vim plugin for working with CMake `compile_commands.json` files.

It provides fourteen commands:

- `:CMakeConfig`
- `:CMakeConfigDefault`
- `:CMakeSwitchPreset`
- `:CMakeSwitchBuild`
- `:CMakeSwitchTarget`
- `:CMakeGenerate`
- `:CMakeBuild`
- `:CMakeTest`
- `:CMakeRun`
- `:CMakeClose`
- `:CMakeInfo`
- `:CMakeMenu`
- `:CMakeMenuFull`
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

This creates `.vim-cmake-naive-config.json` in the nearest ancestor directory that
contains `CMakeLists.txt` (searching from current directory upward). If no
`CMakeLists.txt` is found, the command reports an error.

Apply default local CMake configuration:

```vim
:CMakeConfigDefault
```

This creates/updates `.vim-cmake-naive-config.json` in the nearest ancestor
directory that contains `CMakeLists.txt` (searching upward from current
directory), with:
- `output`: `"build"`
- `preset`: `""`
- `build`: `"Debug"`

If no `CMakeLists.txt` is found, the command reports an error.

On plugin startup, if local config `.vim-cmake-naive-config.json` exists in current
directory or parent directories, all config keys are exported to Vim process
environment variables with `VIM_NAIVE_CMAKE_` prefix (uppercase key names;
non-alphanumeric characters converted to `_`).

Whenever plugin commands update local config (`:CMakeConfig`,
`:CMakeConfigDefault`, `:CMakeConfigSet*`, `:CMakeSwitch*`, and default config
creation inside `:CMakeGenerate`/`:CMakeBuild`/`:CMakeTest`/`:CMakeRun`), these environment variables are
resynced immediately in Vim process. Removed config keys are removed from
`VIM_NAIVE_CMAKE_*` environment as well.

Generate CMake build system from local config:

```vim
:CMakeGenerate
```

This command:
- finds nearest `CMakeLists.txt` from current directory upward
- finds nearest existing `.vim-cmake-naive-config.json`, or creates default config
  at the discovered CMake project root when none exists
- creates `<output>` directory when missing
- when `preset` is non-empty, also creates `<output>/<preset>` when missing
- runs `cmake` with config values:
  - `output` -> `-B <output>` when preset is empty
  - `output` + `preset` -> `-B <output>/<preset>` when preset is non-empty
  - adds `--fresh` to force clean cache regeneration
  - `build` -> `-DCMAKE_BUILD_TYPE=<build>`
  - `preset` -> `--preset <preset>` (when non-empty)
- opens a horizontal split terminal and starts generate there asynchronously
- when started from a non-terminal window, limits generate terminal height to at most 10 lines and never more than half of the main window height
- when started from an active terminal window, keeps terminal window size unchanged
- sets terminal status name while running to:
  - `cmake generate --preset=<preset>` when preset is set
  - `cmake generate` when preset is empty
- renames terminal status name on completion to `Success` or `Failure (<code>)`
- after successful generate completion, scans root `compile_commands.json` from the active build directory
- extracts discovered targets and stores them to `.vim-cmake-naive-cache.json` field `targets`
- splits root `compile_commands.json` into target-local `compile_commands.json` files under corresponding target directories
- reuses previously opened visible build/generate output window when possible; otherwise recreates it
- returns immediately; completion/failures are reported in that terminal/messages

Build project with CMake from local config:

```vim
:CMakeBuild
```

This command:
- finds nearest `CMakeLists.txt` from current directory upward
- finds nearest existing `.vim-cmake-naive-config.json`, or creates default config
  at the discovered CMake project root when none exists
- runs `cmake --build <output>` when `preset` is empty
- runs `cmake --build <output>/<preset>` when `preset` is non-empty
- detects available core count (minimum `1`)
- adds `--parallel <core_count>` to `cmake --build`
- adds `--preset <preset>` when config `preset` is non-empty
- adds `--target <target>` when config `target` is non-empty
- opens a horizontal split terminal and starts the build there asynchronously
- when started from a non-terminal window, limits build terminal height to at most 10 lines and never more than half of the main window height
- when started from an active terminal window, keeps terminal window size unchanged
- sets terminal status name while running to:
  - `cmake build --preset=<preset> --target=<target>` when preset and target are set
  - `cmake build --target=all` when target is empty
  - omits `--preset=...` when preset is empty
- renames terminal status name on completion to `Success` or `Failure (<code>)`
- reuses previously opened visible build output window when possible; otherwise recreates it
- returns immediately; build completion and failures are reported in that terminal/messages

Run tests with CTest from local config:

```vim
:CMakeTest
```

This command:
- finds nearest `CMakeLists.txt` from current directory upward
- finds nearest existing `.vim-cmake-naive-config.json`, or creates default config
  at the discovered CMake project root when none exists
- resolves test working directory from config:
  - `<output>` when preset is empty
  - `<output>/<preset>` when preset is non-empty
- detects available core count (minimum `1`)
- runs `ctest --parallel <core_count>` in that working directory
- opens a horizontal split terminal and starts tests there asynchronously
- when started from a non-terminal window, limits test terminal height to at most 10 lines and never more than half of the main window height
- when started from an active terminal window, keeps terminal window size unchanged
- sets terminal status name while running to:
  - `ctest --preset=<preset>` when preset is set
  - `ctest` when preset is empty
- renames terminal status name on completion to `Success` or `Failure (<code>)`
- reuses previously opened visible build/generate/test output window when possible; otherwise recreates it
- returns immediately; test completion and failures are reported in that terminal/messages

Run current target from local config:

```vim
:CMakeRun
```

This command:
- finds nearest `CMakeLists.txt` from current directory upward
- finds nearest existing `.vim-cmake-naive-config.json`, or creates default config
  at the discovered CMake project root when none exists
- requires config key `target` to be set (use `:CMakeSwitchTarget` first)
- resolves run directory from config:
  - `<output>` when preset is empty
  - `<output>/<preset>` when preset is non-empty
- searches for an executable file matching the selected target under that run directory
- runs the discovered executable in that run directory
- opens a horizontal split terminal and starts execution there asynchronously
- when started from a non-terminal window, limits run terminal height to at most 10 lines and never more than half of the main window height
- when started from an active terminal window, keeps terminal window size unchanged
- sets terminal status name while running to:
  - `cmake run --preset=<preset> --target=<target>` when preset is set
  - `cmake run --target=<target>` when preset is empty
- renames terminal status name on completion to `Success` or `Failure (<code>)`
- reuses previously opened visible build/generate/test/run output window when possible; otherwise recreates it
- returns immediately; completion/failures are reported in that terminal/messages

Close CMake terminal windows spawned by generate/build/test/run:

```vim
:CMakeClose
```

This command:
- closes visible terminal windows created by `:CMakeGenerate`, `:CMakeBuild`, `:CMakeTest`, or `:CMakeRun`
- closes hidden terminal buffers created by this plugin
- resets internal terminal reuse state for subsequent build/generate/test/run commands

Show local CMake configuration in popup table:

```vim
:CMakeInfo
```

This command:
- reads nearest existing `.vim-cmake-naive-config.json`
- shows popup with key/value table (`key | value`)
- uses standard popup style (smooth single-line border, `Pmenu` colors)
- if config is missing, shows:
  `No configuration, please use CMakeConfigDefault to get started`

Open a compact popup command menu for common CMake commands:

```vim
:CMakeMenu
```

This command:
- shows a popup with only these commands: `CMakeBuild`, `CMakeRun`, `CMakeTest`, `CMakeSwitchTarget`
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
- asks for arguments when a selected command requires them (for example `CMakeConfigSetOutput`)
- all selection popups use the same keys: `x`/`Esc` to close, `j`/`k` to move, `b`/`Enter` to choose

Switch local CMake preset from `CMakePresets.json`:

```vim
:CMakeSwitchPreset
```

This command:
- finds nearest `CMakeLists.txt` from current directory upward
- reads `CMakePresets.json` at that project root
- always includes predefined preset `(none)`
- lists selectable configure presets (non-hidden, condition evaluates to true) in sorted order
- prompts through a popup menu for selection (fallback to menu/inputlist) and applies the selected preset directly
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
- reads nearest existing `.vim-cmake-naive-config.json`
- always includes predefined build option `(none)`
- always lists default build types: `Debug`, `Release`, `RelWithDebInfo`, `MinSizeRel`
- prompts through a popup menu for selection (fallback to menu/inputlist) and applies the selected build type directly
- removes `preset` key from local config after applying selected build type
- when `none` is selected, removes `build` key from local config
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
- reads nearest existing `.vim-cmake-naive-config.json`
- reads nearest existing `.vim-cmake-naive-cache.json`
- requires `.vim-cmake-naive-cache.json` to contain key `targets` generated by `:CMakeGenerate`
- resolves build directory from config `output` (relative to config root)
- always includes predefined target `(all)`
- discovers selectable targets from cache key `targets`
- prompts through a popup menu for selection (fallback to inputlist) and writes selected target to config key `target`
- when `all` is selected, removes `target` key from local config
- popup search mode toggles with `Ctrl+I` (press again to exit)
- while search mode is active, every typed character updates filtering immediately (`Backspace` removes, `Ctrl-U` clears)
- while search mode is active, popup title ends with `(Insert)`
- popup entries are ordered and prefixed with a number
- currently selected target is marked with `*`
- popup uses smooth single-line borders with standard Vim popup colors
- popup title has no trailing `:`
- popup width is fixed to 30 and height is dynamic up to 10 lines with scrolling
- copies selected target `compile_commands.json` to `<output>/compile_commands.json`
- when `all` is selected, copies root `compile_commands.json` to `<output>/compile_commands.json`
- if cache file is missing, command reports:
  `No cache found. Please run CMakeGenerate command first.`

Set local CMake output in `.vim-cmake-naive-config.json`:

```vim
:CMakeConfigSetOutput build
:CMakeConfigSetOutput out/build
```

This updates the nearest existing `.vim-cmake-naive-config.json` in current
directory or parent directories. If no local config exists, the command reports
an error (run `:CMakeConfig` or `:CMakeConfigDefault` first).
It also updates `VIM_NAIVE_CMAKE_OUTPUT` in Vim process environment.

## Notes

- Errors are reported through Vim messages with a `[vim-cmake-naive]` prefix.
- All `:CMake*` commands use a shared lock. If another `:CMake*` command is in
  progress, command start is rejected with:
  `CMake: another command <command> is already running`.
