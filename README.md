# vim-cmake-naive

> [!WARNING]
> All code in the repository is written by AI

`vim-cmake-naive` is a Vim plugin for CMake workflows around `compile_commands.json` with async generate/build/test/run commands, popup helpers, and local project config.

## Install (vim-plug)

```vim
Plug 'OlegKarasik/vim-cmake-naive'
```

Then run:

```vim
:PlugInstall
```

## Quick start

1. `:CMakeConfigDefault`
2. `:CMakeGenerate`
3. `:CMakeSwitchTarget` (optional)
4. `:CMakeBuild`, `:CMakeTest`, `:CMakeRun`

Local files used by the plugin:
- `.vim-cmake-naive-config.json`
- `.vim-cmake-naive-cache.json`

## Commands (short list)

- **Configuration:** `:CMakeConfig`, `:CMakeConfigDefault`, `:CMakeConfigSetOutput <value>`
- **Switching:** `:CMakeSwitchPreset`, `:CMakeSwitchBuild`, `:CMakeSwitchTarget`
- **Workflow:** `:CMakeGenerate`, `:CMakeBuild`, `:CMakeTest`, `:CMakeRun`
- **UI:** `:CMakeShowPreview`, `:CMakeHidePreview`, `:CMakeCancel`, `:CMakeClose`, `:CMakeInfo`, `:CMakeMenu`, `:CMakeMenuFull`

## `<Plug>` mappings

The plugin defines `<Plug>(...)` mappings for all `:CMake*` commands and does not create keybindings automatically.

```vim
nmap <leader>cg <Plug>(CMakeGenerate)
nmap <leader>cb <Plug>(CMakeBuild)
nmap <leader>ct <Plug>(CMakeTest)
```

`<Plug>(CMakeConfigSetOutput)` opens `:CMakeConfigSetOutput ` in command-line mode so you can enter the value.

## Wiki

Detailed documentation is maintained in the GitHub Wiki:

| Topic | Link |
| --- | --- |
| Start page | [Wiki Home](https://github.com/OlegKarasik/vim-cmake-naive/wiki) |
| Installation and first run | [Getting Started](https://github.com/OlegKarasik/vim-cmake-naive/wiki/Getting-Started) |
| Config, cache, and output layout | [Configuration](https://github.com/OlegKarasik/vim-cmake-naive/wiki/Configuration) |
| Full command behavior | [Commands Overview](https://github.com/OlegKarasik/vim-cmake-naive/wiki/Commands-Overview) |
| Popup behavior and keybindings | [Popup UI and Navigation](https://github.com/OlegKarasik/vim-cmake-naive/wiki/Popup-UI-and-Navigation) |
| Public API and mappings | [Public API and Plug Mappings](https://github.com/OlegKarasik/vim-cmake-naive/wiki/Public-API-and-Plug-Mappings) |
| Troubleshooting | [Troubleshooting](https://github.com/OlegKarasik/vim-cmake-naive/wiki/Troubleshooting) |

Per-command pages are named after each Ex command (for example: `CMakeGenerate`, `CMakeBuild`, `CMakeSwitchTarget`).
