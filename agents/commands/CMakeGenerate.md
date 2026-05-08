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
   1. when `CMakePresets.json` is present and has detected configure presets,
      runs configure for **all** detected presets:
      `cmake -S <root> -B <output>/<preset> --fresh --preset <preset>`
   2. otherwise, if config `preset` is non-empty, uses
      `cmake -S <root> -B <generation-dir> --fresh --preset <preset>`
   3. otherwise uses
      `cmake -S <root> -B <generation-dir> --fresh -DCMAKE_BUILD_TYPE=<build>`
6. Runs in hidden plugin terminal buffer by default.
   1. Before each hidden run, wipes existing hidden plugin-managed CMake
      terminal buffers.
7. Terminal log ends by printing an empty line followed by the executed command
   line prefixed with `[Command]:`.
8. If a plugin CMake preview window is already visible, it reuses that preview
   window and streams generate output there.
9. While running, updates global statusline immediately with warning highlight
   and command label plus elapsed runtime
   (for example `cmake generate --preset=<preset> [00:00:05]`).
10. On completion, restores global statusline to its pre-command value and writes
   Vim message with command label, runtime, and `[Success]` or `[Error]`
   suffix.
11. On successful completion:
    1. reads root `compile_commands.json` from scan directory
    2. discovers available targets
    3. updates `.vim-cmake-naive-cache.json` key `targets`
    4. splits root compile database into target-local compile databases
    5. when config `target` is non-empty, reapplies that target selection
       (same effect as `CMakeSwitchTarget` for that target)
