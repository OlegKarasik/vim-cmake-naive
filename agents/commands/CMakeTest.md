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
6. Runs asynchronously in hidden plugin terminal buffer by default.
7. Terminal log ends by printing an empty line followed by the executed command
   line prefixed with `[Command]:`.
8. If a plugin CMake preview window is already visible, it reuses that preview
   window and streams test output there.
9. While running, updates global statusline immediately with warning highlight
   and command label plus elapsed runtime
   (for example `ctest --preset=<preset> [00:00:05]`).
10. On completion, restores global statusline to its pre-command value and writes
   Vim message with command label, runtime, and `[Success]` or `[Error]`
   suffix.
