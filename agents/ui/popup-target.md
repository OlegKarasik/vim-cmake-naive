# Target Selection Popup (`:CMakeSwitchTarget`)

**Scope:** Target popup specifics.
**Trigger keywords:** target popup, Select target, target selector.
**Depends on:** `agents/ui/popups-shared.md`.
**Conflicts:** none.

1. Title starts as `Select target`.
2. `(all)` is displayed as the first option.
3. All rows are numbered (`1.`, `2.`, ...).
4. Current target is marked with `*` (or `(all)` when target key is missing).
5. On confirm, invokes `CMakeSwitchTarget`.

