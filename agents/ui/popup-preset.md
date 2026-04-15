# Preset Selection Popup (`:CMakeSwitchPreset`)

**Scope:** Preset popup specifics.
**Trigger keywords:** preset popup, Select preset, preset list.
**Depends on:** `agents/ui/popups-shared.md`.
**Conflicts:** none.

1. Title starts as `Select preset`.
2. `(none)` is displayed as the first option.
3. All rows are numbered (`1.`, `2.`, ...).
4. Current preset is marked with `*`.
5. On confirm, invokes `CMakeSwitchPreset`.

