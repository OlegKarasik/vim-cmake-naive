# CMakeConfigSetOutput `<value>`

**Scope:** `:CMakeConfigSetOutput` behavior.
**Trigger keywords:** CMakeConfigSetOutput, output path, config output.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Requires local configuration to exist.
2. Validates that `<value>` is non-empty.
3. Resolves Local Configuration in current directory or parent directories.
4. Sets `output` to the exact provided string.
5. Updates integration state files, including recalculated
   `.vim-cmake-naive-output` based on current `preset`.

