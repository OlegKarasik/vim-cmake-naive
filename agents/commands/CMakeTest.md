# CMakeTest

**Scope:** `:CMakeTest` behavior.
**Trigger keywords:** CMakeTest, ctest, run tests.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Resolves Root Directory.
2. Resolves Local Configuration, creating default config if missing.
3. Resolves test working directory from `output` and optional `preset`.
4. Ensures test directory exists.
5. Starts asynchronous terminal command in that directory:
   1. `ctest --parallel <N>`
6. Runs asynchronously in hidden plugin terminal buffer by default (no automatic
   preview window).
7. While running, sets Vim status line to the terminal title for this command
   using Vim built-in warning highlight group `WarningMsg`.
8. Reports progress when started and final result (success/failure) via messages.
