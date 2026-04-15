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
   1. `cmake -S <root> -B <generation-dir> --fresh -DCMAKE_BUILD_TYPE=<build>`
   2. adds `--preset <preset>` when preset is non-empty
6. Uses plugin terminal split/reuse system (horizontal split, reusable terminal
   window, command status naming).
7. On successful completion:
   1. reads root `compile_commands.json` from scan directory
   2. discovers available targets
   3. updates `.vim-cmake-naive-cache.json` key `targets`
   4. splits root compile database into target-local compile databases

