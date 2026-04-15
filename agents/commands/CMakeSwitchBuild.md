# CMakeSwitchBuild

**Scope:** `:CMakeSwitchBuild` behavior.
**Trigger keywords:** CMakeSwitchBuild, build type picker, Debug Release.
**Depends on:** `agents/core/concepts.md`, `agents/ui/popup-build.md`.
**Conflicts:** none.

1. Requires local configuration to exist.
2. Resolves Local Configuration.
3. Uses current Local Configuration to resolve current build value.
4. Presents options: `(none)`, `Debug`, `Release`, `RelWithDebInfo`, `MinSizeRel`.
5. Shows Build Selection popup when popup support exists; otherwise uses
   menu/inputlist fallback.
6. On selection:
   1. `(none)` removes `build`
   2. build name sets `build` and removes `preset`

