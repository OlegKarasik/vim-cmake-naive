# CMakeMake

**Scope:** `:CMakeMake` / `:CMakeMake!` behavior.
**Trigger keywords:** CMakeMake, CMakeMake!, :make, quickfix build flow.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Explicit command for running the Vim `:make` / `:make!` flow with plugin
   config resolution.
2. Resolves Root Directory.
3. Resolves Local Configuration, creating default config if missing.
4. Computes the same `cmake --build ...` command as CMakeBuild.
5. Runs `:make`/`:make!` with that command so quickfix is populated.
6. Applies `g:vim_cmake_naive_make_errorformat` override when set.
7. On failure, opens quickfix when `g:vim_cmake_naive_open_quickfix_on_error` is
   enabled.

