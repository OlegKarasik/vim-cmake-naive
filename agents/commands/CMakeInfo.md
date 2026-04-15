# CMakeInfo

**Scope:** `:CMakeInfo` behavior.
**Trigger keywords:** CMakeInfo, config table, info popup.
**Depends on:** `agents/core/concepts.md`, `agents/ui/popup-information.md`.
**Conflicts:** none.

1. Resolves Local Configuration.
2. Reads nearest existing Local Configuration.
3. If config exists:
   1. sorts keys
   2. renders aligned `key | value` table
   3. title includes config filename: `CMake info [.vim-cmake-naive-config.json]`
4. If config is missing, displays one-line guidance:
   `No configuration, please use CMakeConfigDefault to get started`
5. Opens Information Popup.

