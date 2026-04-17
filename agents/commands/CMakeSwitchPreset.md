# CMakeSwitchPreset

**Scope:** `:CMakeSwitchPreset` behavior.
**Trigger keywords:** CMakeSwitchPreset, preset picker, configurePresets.
**Depends on:** `agents/core/concepts.md`, `agents/ui/popup-preset.md`.
**Conflicts:** none.

1. Requires local configuration to exist.
2. Resolves Root Directory (current working directory first, then current file
   path as fallback), then reads `CMakePresets.json`.
3. Resolves Local Configuration.
4. Builds selectable preset list from `configurePresets`:
   1. skips hidden presets
   2. evaluates supported preset conditions (`const`, `equals`, `notequals`,
      `inList`, `notInList`, `matches`, `notMatches`, `anyOf`, `allOf`, `not`)
   3. resolves inheritance and rejects cycles/missing parents
5. Prepends synthetic option `(none)`.
6. Shows Preset Selection popup when popup support exists; otherwise uses
   menu/inputlist fallback.
7. On selection:
   1. `(none)` removes `preset`
   2. any preset name sets `preset` and removes `build`
