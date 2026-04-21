# CMakeSwitchTarget

**Scope:** `:CMakeSwitchTarget` behavior.
**Trigger keywords:** CMakeSwitchTarget, target picker, switch target, cache targets.
**Depends on:** `agents/core/concepts.md`, `agents/ui/popup-target.md`.
**Conflicts:** none.

1. Requires local configuration to exist.
2. Requires Local Cache with `targets` array (usually produced by `:CMakeGenerate`).
3. If cache file is missing, reports built-in error:
   `No cache found. Please run CMakeGenerate command first.`
4. Resolves Local Configuration.
5. Resolves Build Directory and Scan Directory from config.
6. Prepends synthetic option `(all)` to cached targets.
7. Shows Target Selection popup when popup support exists; otherwise inputlist fallback.
8. On selection:
   1. `(all)`:
      1. copies root `<scan-directory>/compile_commands.json` to
         `<output>/compile_commands.json`
      2. removes `target` key from config
   2. specific target:
      1. resolves `.../CMakeFiles/<target>.dir`
      2. copies that target-local `compile_commands.json` to
         `<output>/compile_commands.json`
      3. sets `target` key in config
9. Updates local `.vimspector` integration variable values through config
   writes when those variable definitions already exist.
