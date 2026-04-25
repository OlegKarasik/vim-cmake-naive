# CMakeBuild

**Scope:** `:CMakeBuild` behavior.
**Trigger keywords:** CMakeBuild, cmake --build, parallel build, quickfix parse.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Resolves Root Directory.
2. Resolves Local Configuration, creating default config if missing.
3. Resolves target build directory from `output` and optional `preset`.
4. Detects parallelism:
   1. `$NUMBER_OF_PROCESSORS` first
   2. then platform commands (`sysctl` / `nproc` / `getconf`)
   3. fallback `1`
5. Builds command:
   1. `cmake --build <dir> --parallel <N>`
   2. adds `--preset <preset>` when preset is set
   3. adds `--target <target>` when target is set
6. Runs asynchronously in hidden plugin terminal buffer by default.
7. Terminal log starts by printing the executed command line prefixed with
   `[Command]:`.
8. If a plugin CMake preview window is already visible, it reuses that preview
   window and streams build output there.
9. While running, updates global statusline immediately with warning highlight
   and terminal title plus elapsed runtime
   (for example `cmake build --target=all [00:00:05]`).
10. On completion, restores global statusline to its pre-command value and writes
   Vim message with terminal title, runtime, and `[Success]` or `[Error]`
   suffix.
11. Clears existing quickfix entries before command execution.
12. On failure, parses terminal output into quickfix entries:
   1. uses `g:vim_cmake_naive_make_errorformat` when set
   2. otherwise uses Vim `errorformat`
   3. opens quickfix on failure when `g:vim_cmake_naive_open_quickfix_on_error` is
      enabled and entries were parsed
