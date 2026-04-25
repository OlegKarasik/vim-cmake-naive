# CMakeGenerate

**Scope:** `:CMakeGenerate` behavior.
**Trigger keywords:** CMakeGenerate, cmake -S, configure, generate targets.
**Depends on:** `agents/core/concepts.md`.
**Conflicts:** none.

1. Resolves Root Directory.
2. Resolves Local Configuration, creating default config if missing.
3. Computes output directories from `output` and optional `preset`.
4. Ensures output directories exist.
5. Starts asynchronous terminal command:
   1. `cmake -S <root> -B <generation-dir> --fresh --preset <preset>` when
      preset is non-empty
   2. otherwise uses
      `cmake -S <root> -B <generation-dir> --fresh -DCMAKE_BUILD_TYPE=<build>`
6. Runs in hidden plugin terminal buffer by default.
7. If a plugin CMake preview window is already visible, it reuses that preview
   window and streams generate output there.
8. While running, updates global statusline immediately with warning highlight
   and terminal title plus elapsed runtime
   (for example `cmake generate --preset=<preset> [00:00:05]`).
9. On completion, restores global statusline to its pre-command value and writes
   Vim message with terminal title, runtime, and `[Success]` or `[Error]`
   suffix.
10. On successful completion:
   1. reads root `compile_commands.json` from scan directory
   2. discovers available targets
   3. updates `.vim-cmake-naive-cache.json` key `targets`
   4. splits root compile database into target-local compile databases
