# CMakeClose

**Scope:** `:CMakeClose` behavior.
**Trigger keywords:** CMakeClose, close terminal, wipe terminal buffers.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Closes all visible plugin-managed terminal windows.
2. Wipes hidden plugin-managed terminal buffers.
3. Resets remembered reusable terminal state.
4. Clears pending terminal success callbacks.

