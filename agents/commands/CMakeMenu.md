# CMakeMenu

**Scope:** `:CMakeMenu` behavior.
**Trigger keywords:** CMakeMenu, compact command menu.
**Depends on:** `agents/ui/popup-command-menu.md`.
**Conflicts:** none.

1. Opens command menu for compact set:
   1. `CMakeBuild`
   2. `CMakeRun`
   3. `CMakeTest`
   4. `CMakeSwitchTarget`
   5. `CMakeSwitchPreset`
2. Uses Command Menu popup when popup support exists; otherwise list/menu fallback.
3. Runs selected command with `silent`.

