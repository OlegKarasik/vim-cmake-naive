# CMakeMenuFull

**Scope:** `:CMakeMenuFull` behavior.
**Trigger keywords:** CMakeMenuFull, full command menu, command argument prompt.
**Depends on:** `agents/ui/popup-command-menu.md`.
**Conflicts:** none.

1. Opens command menu for full command set:
   1. `CMakeConfig`
   2. `CMakeConfigDefault`
   3. `CMakeSwitchPreset`
   4. `CMakeSwitchBuild`
   5. `CMakeSwitchTarget`
   6. `CMakeGenerate`
   7. `CMakeBuild`
   8. `CMakeTest`
   9. `CMakeRun`
   10. `CMakeShowPreview`
   11. `CMakeHidePreview`
   12. `CMakeCancel`
   13. `CMakeClose`
   14. `CMakeInfo`
   15. `CMakeMenu`
   16. `CMakeMenuFull`
   17. `CMakeConfigSetOutput`
2. Uses Command Menu popup when popup support exists; otherwise list/menu fallback.
3. Only commands that currently exist in Vim are shown.
4. For commands requiring args (`CMakeConfigSetOutput`), prompts:
   `Arguments for <Command>: `.
5. Empty args cancel execution for that command.
6. Runs selected command with `silent`.
