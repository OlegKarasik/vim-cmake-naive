# CMakeShowPreview

**Scope:** `:CMakeShowPreview` behavior.
**Trigger keywords:** CMakeShowPreview, show preview, terminal output preview.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Resolves most recent plugin-managed terminal buffer produced by:
   1. `CMakeGenerate`
   2. `CMakeBuild`
   3. `CMakeTest`
   4. `CMakeRun`
2. Opens/reuses a bottom preview window.
3. Shows the resolved terminal buffer in that preview window.
4. If already invoked from that preview terminal window, does nothing.
5. While visible, subsequent `CMakeGenerate`, `CMakeBuild`, `CMakeTest`, and
   `CMakeRun` commands reuse this preview window and stream their output there.
6. Reports an error when no recent CMake terminal output exists.
7. Does not acquire the command lock, so it can run while another terminal
   CMake command is active.
