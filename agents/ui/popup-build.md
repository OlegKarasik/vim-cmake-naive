# Build Selection Popup (`:CMakeSwitchBuild`)

**Scope:** Build popup specifics.
**Trigger keywords:** build popup, Select build, build type selector.
**Depends on:** `agents/ui/popups-shared.md`.
**Conflicts:** none.

1. Title starts as `Select build`.
2. `(none)` plus default build types are displayed.
3. All rows are numbered (`1.`, `2.`, ...).
4. Current build is marked with `*`.
5. On confirm, invokes `CMakeSwitchBuild`.

