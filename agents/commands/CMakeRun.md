# CMakeRun

**Scope:** `:CMakeRun` behavior.
**Trigger keywords:** CMakeRun, run target, executable lookup.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Requires non-empty `target` in config; otherwise reports:
   `No target selected. Please use CMakeSwitchTarget command first.`
2. Resolves Root Directory.
3. Resolves Local Configuration, creating default config if missing.
4. Resolves run directory from `output` and optional `preset`.
5. Resolves executable path for target:
   1. checks direct candidate names (`<target>`, and on Windows also
      `.exe/.bat/.cmd`)
   2. checks `<run-dir>/<build>/<candidate>` when `build` value is set
   3. falls back to recursive search under run directory
   4. excludes files under `CMakeFiles/`
   5. requires exactly one executable match
6. Starts asynchronous terminal command for discovered executable in run
   directory.
7. Runs asynchronously in hidden plugin terminal buffer by default.
8. If a plugin CMake preview window is already visible, it reuses that preview
   window and streams run output there.
9. While running, updates global statusline immediately with warning highlight
   and terminal title plus elapsed runtime
   (for example `cmake run --target=<target> [00:00:05]`).
10. On completion, restores global statusline to its pre-command value and writes
    Vim message with terminal title, runtime, and `[Success]` or `[Error]`
    suffix.
