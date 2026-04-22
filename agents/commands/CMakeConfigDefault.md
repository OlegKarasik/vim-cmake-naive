# CMakeConfigDefault

**Scope:** `:CMakeConfigDefault` behavior.
**Trigger keywords:** CMakeConfigDefault, default config values.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Resolves Root Directory.
2. Resolves Local Configuration at that root.
3. Creates config when missing, or updates existing config.
4. Writes default keys:
   1. `output = "build"`
   2. `preset = ""`
   3. `build = "Debug"`
5. Preserves unrelated custom keys in existing config.
6. Updates local `.vimspector.json` integration variable values when those variable
   definitions already exist.
