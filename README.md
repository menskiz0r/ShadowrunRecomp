# Shadowrun (Sega Genesis) — native PC port

> **⚠ WORK IN PROGRESS - NOT PLAYABLE.** This is a research port, not a finished
> game: it boots, renders and plays audio, but known defects break combat and the
> Start menu, and at least one crash is open. See [STATUS.md](STATUS.md) for the
> current known-issues list.


A native Windows port of **Shadowrun** (Sega Genesis, 1994) produced by static
recompilation: the original 68000 code is translated to C and run against a
Genesis runtime, so the game executes as native code with no emulator in the
loop.

Built on [**segagenesisrecomp**](https://github.com/mstan/segagenesisrecomp) by
[**Matthew Stanley (mstan)**](https://github.com/mstan) — the recompiler, the
Genesis runtime, the audio path and the SDL front-end are his work, used here as
a submodule and credited in [`CREDITS.md`](CREDITS.md). Part of the R.A.I.D. /
RetroPortingToolkit community.

**You must supply your own ROM.** This repository contains no game code, no
graphics, no audio and no save files.

## What you need

| | |
|---|---|
| ROM | Shadowrun (USA), 2 097 152 bytes, CRC32 `FBB92909`, SHA-1 `A06A281D39E845BFF446A541B2FF48E1D93143C2` |
| OS | Windows 10/11 x64 |
| Toolchain | [w64devkit](https://github.com/skeeto/w64devkit) (GCC 16.2) |
| Framework | [segagenesisrecomp](https://github.com/mstan/segagenesisrecomp) v0.1.2, pinned as a submodule |

## Build

```powershell
# 1. build the recompiler from the pinned framework
powershell -ExecutionPolicy Bypass -File scripts\build_recompiler.ps1

# 2. translate the ROM to C   (generated/ is git-ignored, never committed)
build\GenesisRecomp_fixed.exe "<your ROM>" --game config\game.toml --output-dir generated

# 3. build the runner
powershell -ExecutionPolicy Bypass -File scripts\build_runner.ps1
```

## Run

The CMake build produces the playable game - window, keyboard/gamepad input and
audio through the framework's SDL runner:

```powershell
cmake -S . -B build -G "MinGW Makefiles"
cmake --build build -j
build\ShadowrunRecomp.exe "game\shadowrun.bin"
```

The PowerShell build produces a headless harness used by the validation scripts:
deterministic frames, BMP/WAV capture, scripted input, coverage and leak probes:

```powershell
build\shadowrun_runner.exe "<your ROM>" 3000 frame.bmp
```

Both are described in [`docs/SDL-FRONTEND.md`](docs/SDL-FRONTEND.md).

Before building, pin the framework and apply the one patch this game needs:

```powershell
git submodule update --init --recursive
powershell -ExecutionPolicy Bypass -File scripts\apply-framework-patches.ps1
```

Pin `segagenesisrecomp` at **a7e8c5e or later**: always-mapped cartridge SRAM
(required by this cart) landed there on 2026-10-24, after the v0.1.2 release.

Useful environment variables:

| Variable | Effect |
|---|---|
| `DSH_PRESSES="2100:S,2200:A"` | scripted pad presses, `frame:BUTTON` |
| `DSH_SRAM=file.srm` | load/save battery RAM (atomic write) |
| `DSH_WAV=out.wav` | record the mixed audio |
| `DSH_WAV_RATE=48000` | resample on capture |
| `DSH_LEAK=1` | print the live-allocation counter |
| `DSH_POISON_HEAP=1` | fill new allocations with `0xFE` (uninitialised-read check) |

## Validation

```powershell
powershell -ExecutionPolicy Bypass -File scripts\validate.ps1        # 8 checks
powershell -ExecutionPolicy Bypass -File scripts\validate-saves.ps1  # 14 checks
powershell -ExecutionPolicy Bypass -File scripts\compare-reference.ps1
```

The third one diffs frames against BizHawk and needs a copy of BizHawk in
`build\bizhawk`.

## Status

See [`STATUS.md`](STATUS.md) for exactly what is verified, what is not, and what
the known differences from the original hardware are.

## Legal posture

Shadowrun is a trademark of The Topps Company / FASA; the game is © SEGA. This
project is not affiliated with or endorsed by any rights holder.

What this repository contains and does not contain:

| | |
|---|---|
| Contains | a recompiler patch, a per-game adapter (`GameSpec`, host stubs), a build configuration, build/validation scripts and documentation |
| Does **not** contain | the ROM, translated (generated) C, graphics, audio, save files, screenshots, or any prebuilt binary |
| `game/game.toml` | function addresses, seeds and dispatch facts measured from the ROM - configuration data, no code or expressive content |

Static recompilation is, legally, a translation of someone else's program. That
translation is created **on your machine, from the ROM you own**, when you run the
recompiler - the same posture as an emulator: the tool contains no game code, and
the derived work never gets distributed. For that reason:

* **do not publish a compiled `ShadowrunRecomp.exe`** - it embeds translated game
  code and would be a derivative work being distributed;
* do not add screenshots, audio captures, box art or save files to this repo;
* if a rights holder objects, removing this repository removes everything derived
  from their work; there is nothing else to take down.

Obtain the ROM legally, from a cartridge you own.

Our integration code is licensed under the PolyForm Noncommercial License 1.0.0,
matching the framework. See `LICENSE.md` and `THIRD-PARTY.md`.

## Credits

* [segagenesisrecomp](https://github.com/mstan/segagenesisrecomp) by Matthew
  Stanley — the recompiler, runtime, VDP, audio and Z80 support.
* The framework's colour ladder is verified against BlastEm's `vdp.c`.
* ymfm (Aaron Giles) for the YM2612 implementation.
