# Releasing

Build from a clean, committed checkout with initialized submodules and an
owner-supplied USA ROM at `game/shadowrun.bin` (CRC32 `FBB92909`). Never commit
or distribute it.

## Requirements

* Windows 10/11 x64
* [w64devkit](https://github.com/skeeto/w64devkit) (GCC 16.2) on `PATH`
* CMake 3.19+
* Python 3 (the frame-comparison helper)
* `segagenesisrecomp` at **`a7e8c5e` or later** (always-mapped cartridge SRAM
  landed there on 2026-10-24; this cart needs it). The committed submodule
  pointers are the tested ones: `segagenesisrecomp` `48e0f90`, `recomp-ui`
  `cf6315a`

## Build

```powershell
git submodule update --init --recursive
powershell -ExecutionPolicy Bypass -File scripts\apply-framework-patches.ps1
cmake -S . -B build -G "MinGW Makefiles"
cmake --build build -j
```

`build/ShadowrunRecomp.exe` plus `SDL2.dll` is the playable build;
`scripts\build_runner.ps1` produces the headless harness the validators use.

## Validation and publication

1. Run `scripts\validate-all.ps1` and require the results recorded in
   `docs/VALIDATION-REPORT.md`.
2. Run the packaged binary from a fresh folder with an owner-supplied ROM: check
   that the launcher appears (when `recomp-ui` is present), the window opens,
   audio plays and the first scene renders.
3. Never include in a release archive:

| Exclude | Why |
|---|---|
| `game/shadowrun.bin` and any ROM | copyrighted game |
| `generated/` | translated output derived from the ROM |
| `*.srm`, `*.wav`, `*.bmp`, screenshots | game data / imagery |
| `build/` and all binaries except the two shipped | build products |
| `segagenesisrecomp/`, `recomp-ui/` working copies | third-party code, pinned by submodule |
| `w64devkit`, BizHawk, Dr. Memory and other tools | not redistributable here |

4. Keep the notices: `LICENSE.md`, `PERMISSIONS.md`, `THIRD-PARTY.md`,
   `CREDITS.md`.

## Known limitations at 0.1.0

* The SDL front-end is playable and survives a 120 000-frame run, but the
  scripted save route is only automated on the headless harness; see
  `docs/VALIDATION-REPORT.md` for why (input scripting ticks on wall frames, the
  game on simulated frames).
* Campaign coverage is verified through the first room and the save system, not
  the whole game.
