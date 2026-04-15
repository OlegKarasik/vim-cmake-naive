# CMakeConfig

**Scope:** `:CMakeConfig` behavior.
**Trigger keywords:** CMakeConfig, create config, initialize config.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Resolves Root Directory from current working directory.
2. Resolves Local Configuration at that root.
3. Creates `.vim-cmake-naive-config.json` only when it does not already exist.
4. Initial payload is an empty JSON object (`{}`), not default values.
5. Updates integration state files (`.vim-cmake-naive-target`,
   `.vim-cmake-naive-output`) immediately after writing config.
6. If config already exists, command does not overwrite it.

