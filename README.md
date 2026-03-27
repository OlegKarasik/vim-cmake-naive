# cdbm.vim

`cdbm` is now a Vim plugin for working with CMake `compile_commands.json` files.

It provides nine commands:

- `:CdbmSplit <build-directory> [--input <path>] [--output-name <name>] [--dry-run]`
- `:CdbmSwitch <build-directory> <target> [--output <path>]`
- `:CMakeConfig`
- `:CMakeConfigDefault`
- `:CMakeGenerate`
- `:CMakeConfigSetPreset <preset>`
- `:CMakeResetConfigPreset`
- `:CMakeConfigSetBuild <value>`
- `:CMakeConfigSetOutput <value>`

## Install (vim-plug)

```vim
Plug 'YOUR_GITHUB_USER/cdbm'
```

Then run:

```vim
:PlugInstall
```

## Usage

Split one `compile_commands.json` into per-target files:

```vim
:CdbmSplit build --dry-run
:CdbmSplit build
```

Switch active `compile_commands.json` to one target:

```vim
:CdbmSwitch build app
:CdbmSwitch build app --output .
```

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
:CMakeResetConfigPreset
```

This creates the config file if needed and sets the `preset` key to `""`.

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

- Target directories are inferred from `output`, `arguments`, and `command` fields.
- `:CdbmSwitch` expects a target name (for example `app`), not a path.
- Errors are reported through Vim messages with a `[cdbm]` prefix.
