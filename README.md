# vim-cmake-naive

> [!WARNING]
> This plugin was written by AI, except for `AGENTS.md`.

`vim-cmake-naive` is a Vim plugin for working with CMake `compile_commands.json` files.

It provides sixteen primary commands:

- `:CMakeConfig`
- `:CMakeConfigDefault`
- `:CMakeSwitchPreset`
- `:CMakeSwitchBuild`
- `:CMakeSwitchTarget`
- `:CMakeGenerate`
- `:CMakeBuild`
- `:CMakeTest`
- `:CMakeRun`
- `:CMakeShowPreview`
- `:CMakeHidePreview`
- `:CMakeClose`
- `:CMakeInfo`
- `:CMakeMenu`
- `:CMakeMenuFull`
- `:CMakeConfigSetOutput <value>`

## `<Plug>` support

The plugin defines `<Plug>(<command>)` mappings for all `:CMake*` commands by
default, but does not create keybindings by itself.

Then map your preferred keys:

```vim
nmap <leader>cg <Plug>(CMakeGenerate)
nmap <leader>cb <Plug>(CMakeBuild)
nmap <leader>ct <Plug>(CMakeTest)
```

`<Plug>(CMakeConfigSetOutput)` opens `:CMakeConfigSetOutput ` in command-line mode
so you can type the output value.

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
- starts generate asynchronously in a hidden plugin terminal buffer (no automatic preview window)
- sets terminal status name while running to:
  - `cmake generate --preset=<preset>` when preset is set
  - `cmake generate` when preset is empty
- after successful generate completion, scans root `compile_commands.json` from the active build directory
- extracts discovered targets and stores them to `.vim-cmake-naive-cache.json` field `targets`
- splits root `compile_commands.json` into target-local `compile_commands.json` files under corresponding target directories
- returns immediately; start progress and completion result are reported in messages

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
- starts build asynchronously in a hidden plugin terminal buffer (no automatic preview window)
- sets terminal status name while running to:
  - `cmake build --preset=<preset> --target=<target>` when preset and target are set
  - `cmake build --target=all` when target is empty
  - omits `--preset=...` when preset is empty
- when the build fails, parses terminal output into quickfix entries
  - uses `g:vim_cmake_naive_make_errorformat` when set
  - otherwise uses Vim `errorformat`
- when `g:vim_cmake_naive_open_quickfix_on_error = 1`, opens quickfix automatically for failed builds with parsed entries
- returns immediately; start progress and completion result are reported in messages

Run build through Vim `:make`/quickfix flow:

```vim
:CMakeMake!
```

This command resolves/creates local config exactly like `:CMakeBuild`, computes
the same `cmake --build ...` command, runs it via `:make!`, and reports the same
build success/failure summary. Optional arguments are forwarded to `:make`.

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
- starts tests asynchronously in a hidden plugin terminal buffer (no automatic preview window)
- sets terminal status name while running to:
  - `ctest --preset=<preset>` when preset is set
  - `ctest` when preset is empty
- returns immediately; start progress and completion result are reported in messages

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
- starts execution asynchronously in a hidden plugin terminal buffer (no automatic preview window)
- sets terminal status name while running to:
  - `cmake run --preset=<preset> --target=<target>` when preset is set
  - `cmake run --target=<target>` when preset is empty
- returns immediately; start progress and completion result are reported in messages

Show preview window with the most recent CMake terminal output:

```vim
:CMakeShowPreview
```

This command:
- opens/reuses a bottom preview window
- shows terminal output from the most recent `:CMakeGenerate`, `:CMakeBuild`, `:CMakeTest`, or `:CMakeRun`
- reports an error when no recent CMake terminal output is available

Hide visible CMake preview windows:

```vim
:CMakeHidePreview
```

This command:
- closes visible preview windows containing plugin CMake terminal output
- keeps terminal buffers hidden so `:CMakeShowPreview` can reopen them later

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
- keeps popup width within 10..30 columns
- if config is missing, shows:
  `No configuration, please use CMakeConfigDefault to get started`

Open a compact popup command menu for common CMake commands:

```vim
:CMakeMenu
```

This command:
- shows a popup with only these commands: `CMakeBuild`, `CMakeRun`, `CMakeTest`, `CMakeSwitchTarget`
- uses the same popup style as other selection popups (fixed width 30, smooth borders, dynamic height up to 10)
- popup search mode toggles with `Ctrl+I` (press again to exit)
- while search mode is active, every typed character updates filtering immediately (`Backspace` removes, `Ctrl-U` clears)
- while search mode is active, popup title ends with `(Insert)`
- exiting search mode keeps the current filter result
- shows numbered entries without a current-item `*` marker
- executes the selected command

Open a full popup command menu for all plugin CMake commands:

```vim
:CMakeMenuFull
```

This command:
- shows a popup with all available `CMake*` Ex commands from this plugin
- uses the same popup style as other selection popups (fixed width 30, smooth borders, dynamic height up to 10)
- popup search mode toggles with `Ctrl+I` (press again to exit)
- while search mode is active, every typed character updates filtering immediately (`Backspace` removes, `Ctrl-U` clears)
- while search mode is active, popup title ends with `(Insert)`
- exiting search mode keeps the current filter result
- shows numbered entries without a current-item `*` marker
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
- popup search mode toggles with `Ctrl+I` (press again to exit)
- while search mode is active, every typed character updates filtering immediately (`Backspace` removes, `Ctrl-U` clears)
- while search mode is active, popup title ends with `(Insert)`
- exiting search mode keeps the current filter result
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
- popup search mode toggles with `Ctrl+I` (press again to exit)
- while search mode is active, every typed character updates filtering immediately (`Backspace` removes, `Ctrl-U` clears)
- while search mode is active, popup title ends with `(Insert)`
- exiting search mode keeps the current filter result
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
- exiting search mode keeps the current filter result
- popup entries are ordered and prefixed with a number
- currently selected target is marked with `*`
- popup uses smooth single-line borders with standard Vim popup colors
- popup title has no trailing `:`
- popup width is fixed to 30 and height is dynamic up to 10 lines with scrolling
- copies selected target `compile_commands.json` to `<output>/compile_commands.json`
- when `all` is selected, copies root `compile_commands.json` to `<output>/compile_commands.json`
- updates root `.vim-cmake-naive-target` with selected target name (`all` for the `(all)` selection)
- if cache file is missing, command reports:
  `No cache found. Please run CMakeGenerate command first.`

Set local CMake output in `.vim-cmake-naive-config.json`:

```vim
:CMakeConfigSetOutput build
:CMakeConfigSetOutput out/build
```

This updates the nearest existing `.vim-cmake-naive-config.json` in current
directory or parent directories. If no local config exists, the command reports
an error (run `:CMakeConfig` or `:CMakeConfigDefault` first). It also updates
root `.vim-cmake-naive-output` with the build directory path relative to the
root (`<output>` or `<output>/<preset>`).

## `:make` / quickfix integration

Use `:CMakeMake`/`:CMakeMake!` directly to run the same build flow as
`:CMakeBuild` through Vim quickfix:
- resolves nearest CMake root and local config
- creates default local config when missing
- builds with the same `cmake --build ... --parallel ... [--preset] [--target]`
  command
- reports the same success/failure summary and keeps quickfix population

For scripts/non-interactive calls, use `:CMakeMake!`.

Optional global settings:

```vim
" Optional: keep global &makeprg synchronized whenever config is written
" (useful for external tooling that reads &makeprg):
let g:vim_cmake_naive_sync_makeprg = 1

" Optional quickfix parser override used by failed :CMakeBuild and :make! / :CMakeMake:
let g:vim_cmake_naive_make_errorformat = '%f:%l:%c: %m'

" Optional: open quickfix window automatically for failed :CMakeBuild, :make! / :CMakeMake builds:
let g:vim_cmake_naive_open_quickfix_on_error = 1
```

## Notes

- Errors are reported through Vim messages with a `[vim-cmake-naive]` prefix.
- Integration files are maintained at project root:
  - `.vim-cmake-naive-target`: currently selected target name (empty when unset)
  - `.vim-cmake-naive-output`: current build directory path relative to root
- All `:CMake*` commands use a shared lock. If another `:CMake*` command is in
  progress, command start is rejected with:
  `CMake: another command <command> is already running`.
