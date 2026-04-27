# CMakeCancel

**Scope:** `:CMakeCancel` behavior.
**Trigger keywords:** CMakeCancel, cancel terminal job, stop running command.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Finds the currently active plugin-managed terminal job.
2. Stops that terminal job immediately.
3. Releases command lock when no plugin terminal jobs remain running.
4. Reports:
   1. `No active CMake terminal job to cancel.` when nothing is running.
   2. `Canceled active CMake terminal job: <name>.` on success.
