# Agent Routing Index

This repository uses split agent guidance. Load only files that match the prompt.

## Global Rules (always apply)

1. DO NOT create or edit files outside of repository.
2. DO NOT redirect output from commands into files outside of repository.
3. DO NOT take dependencies on other plugins.

## Core Docs

| Topic | File |
| --- | --- |
| Global constraints only | `agents/core/rules.md` |
| Shared definitions and lifecycle concepts | `agents/core/concepts.md` |

## Command Docs

Prefer the exact command-named file when prompt text mentions a command name.

| Prompt mentions | File |
| --- | --- |
| `CMakeConfig` | `agents/commands/CMakeConfig.md` |
| `CMakeConfigDefault` | `agents/commands/CMakeConfigDefault.md` |
| `CMakeConfigSetOutput` | `agents/commands/CMakeConfigSetOutput.md` |
| `CMakeSwitchPreset` | `agents/commands/CMakeSwitchPreset.md` |
| `CMakeSwitchBuild` | `agents/commands/CMakeSwitchBuild.md` |
| `CMakeSwitchTarget` | `agents/commands/CMakeSwitchTarget.md` |
| `CMakeGenerate` | `agents/commands/CMakeGenerate.md` |
| `CMakeBuild` | `agents/commands/CMakeBuild.md` |
| `CMakeMake`, `CMakeMake!`, `:make`, quickfix build flow | `agents/commands/CMakeMake.md` |
| `CMakeTest` | `agents/commands/CMakeTest.md` |
| `CMakeRun` | `agents/commands/CMakeRun.md` |
| `CMakeClose` | `agents/commands/CMakeClose.md` |
| `CMakeInfo` | `agents/commands/CMakeInfo.md` |
| `CMakeMenu` | `agents/commands/CMakeMenu.md` |
| `CMakeMenuFull` | `agents/commands/CMakeMenuFull.md` |

## Popup / UI Docs

| Prompt mentions | File |
| --- | --- |
| generic popup behavior, navigation keys, search mode | `agents/ui/popups-shared.md` |
| `CMakeInfo` information popup styling/content | `agents/ui/popup-information.md` |
| preset popup details | `agents/ui/popup-preset.md` |
| build popup details | `agents/ui/popup-build.md` |
| target popup details | `agents/ui/popup-target.md` |
| command menu popup details | `agents/ui/popup-command-menu.md` |

## API Docs (No Ex command wrapper)

| Prompt mentions | File |
| --- | --- |
| `<Plug>(...)` mappings | `agents/api/plug-mappings.md` |
| `vim_cmake_naive#split`, `#switch`, config setters, startup sync | `agents/api/public-functions.md` |

## Lookup Guidance

1. Start with `agents/core/rules.md` only when the prompt is about constraints.
2. Load `agents/core/concepts.md` for shared terms (root, config, cache, output dirs).
3. Load one command file per command in prompt; avoid unrelated command files.
4. Load popup files only when the prompt asks about popup behavior or interaction keys.
