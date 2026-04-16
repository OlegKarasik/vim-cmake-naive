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
6. Runs in the plugin terminal split/reuse backend (asynchronous).
7. On failure, parses terminal output into quickfix entries:
   1. uses `g:vim_cmake_naive_make_errorformat` when set
   2. otherwise uses Vim `errorformat`
   3. opens quickfix on failure when `g:vim_cmake_naive_open_quickfix_on_error` is
      enabled and entries were parsed
   4. rewrites clang-style `note:` entries to
      `<source line> (note: ...)` when source location is available
