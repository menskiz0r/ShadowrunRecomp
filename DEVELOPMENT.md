# Development

## Layout

```
segagenesisrecomp/     framework submodule: recompiler + Genesis runtime + SDL front-end
game/                  the Shadowrun integration
  game.toml              ROM identity, seeded functions, dispatch/mode tables
  adapter.c              host adapter (frame loop, input, audio capture, SRAM, probes)
  host_stubs.c           runtime hooks the headless host must provide
  sdl_stubs.c            SDL surface the headless build does not use
  bmp.c                  framebuffer dump
  leak_probe.c           allocation counter (`--wrap` based)
tests/                 comparison helpers used by the validation scripts
scripts/               build + validation scripts
docs/                  per-milestone notes, runner and recompiler notes, upstream research
generated/             translated C (git-ignored; regenerate with regen.bat)
build/                 toolchain, framework checkout, objects, exe (git-ignored)
```

## Toolchain

* Windows 10/11 x64
* [w64devkit](https://github.com/skeeto/w64devkit) — unpack to
  `build/w64devkit/w64devkit/bin`
* The framework submodule: `git submodule update --init --recursive`

## Build

```powershell
git submodule update --init --recursive     # framework + its own submodules + recomp-ui
powershell -ExecutionPolicy Bypass -File scripts\apply-framework-patches.ps1

# recompiler (framework's sources, GCC build)
powershell -ExecutionPolicy Bypass -File scripts\build_recompiler.ps1

# translate the ROM -> generated/*.c   (never committed)
regen.bat

# runner
powershell -ExecutionPolicy Bypass -File scripts\build_runner.ps1
```

`regen.bat` and `_build_native.bat` are thin wrappers around those scripts so the
repo matches the other game projects' habit of double-clickable entry points.

## Regenerating after a game.toml change

`game/game.toml` is the source of truth. After editing it, run `regen.bat` and
rebuild; never hand-edit `generated/`.

The seeded addresses in `game.toml` exist for a reason — each one was added
because the game reached it and the recompiler had not proven it. Removing a seed
without re-running the validation suite will bring a crash back.

## Validation

```powershell
powershell -ExecutionPolicy Bypass -File scripts\validate-all.ps1
```

| Script | Covers |
|---|---|
| `validate.ps1` | boot, no-leak, empty coverage evidence, save round trip, rendering |
| `validate-saves.ps1` | missing / truncated / oversized / garbage `.srm`, second slot, kill mid-run |
| `compare-reference.ps1` | frame diff against BizHawk at fixed checkpoints |

## Debug environment variables

| Variable | Effect |
|---|---|
| `DSH_PRESSES="2100:S,2200:A"` | scripted pad presses (`frame:BUTTON`, `DA` = Down+A same frame) |
| `DSH_SRAM=file.srm` | load/save battery RAM, atomic replace |
| `DSH_WAV=out.wav`, `DSH_WAV_RATE=48000` | audio capture, optional resample |
| `DSH_LEAK=1` | live allocation counter |
| `DSH_POISON_HEAP=1` | fill fresh allocations with `0xFE` |
| `DSH_NO_DC=1` | disable the DC blocker for raw captures |
| `DSH_REPORT`, `DSH_NODE`, `DSH_SEL`, `DSH_PADTEST` | introspection probes |

## Building the SDL front-end

The interactive runner is the framework's `runner/main.c`; this repository
currently builds the headless adapter instead. Wiring the SDL runner needs a
`game/shadowrun_spec.c` (the `GameSpec`: entry points, ROM identity, VBlank/HBlank,
SRAM, pad) and a `CMakeLists.txt` that links `main.c`, the generated code and the
SDL2 libs bundled under `segagenesisrecomp/runner/external/SDL2`. That is the
next step, tracked in `STATUS.md`.
