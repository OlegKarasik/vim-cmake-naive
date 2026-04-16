# CMakeHidePreview

**Scope:** `:CMakeHidePreview` behavior.
**Trigger keywords:** CMakeHidePreview, hide preview, close preview window.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Closes visible preview windows that display plugin-managed CMake terminal output.
2. Keeps terminal buffers hidden (does not wipe them).
3. Keeps latest terminal output available for subsequent `:CMakeShowPreview`.
