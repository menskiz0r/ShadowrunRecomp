# Status

Last updated: 2026-11-09. Everything below was measured on this build; nothing is
assumed.

## What works

| Area | Evidence |
|---|---|
| Boot → SEGA screens → title → menus | frame comparison vs BizHawk, 100 % structural match at aligned checkpoints |
| Archetype / character creation | scripted flow reaches the first room |
| Narrative intro and first room | frame captures + scripted input |
| Walking, map scrolling, collision | walk script moves the character; map scrolls |
| HUD / status panel | Pocket Secretary opens, pages navigate |
| Save / load | "Game Saved!", "Successful download!"; 1 558 bytes written, checksum `1E50BB9A` |
| Audio | FM and PSG both active (peaks 8 457 / 8 182); DC offset removed; verified spectrum |
| Long-run stability | 300 000 frames, no crash, memory decelerating (9.3 → 12.7 MB) |
| No leaks | live-block delta constant at 31 across 3 k–40 k frames |
| No untranslated paths | dispatch / interior-label / coverage evidence files empty after the full flow |
| Save robustness | missing, truncated, oversized, garbage, slot 2, kill-mid-run — 14/14 |

## What is NOT done

| Area | Reality |
|---|---|
| **Interactive front-end** | **now built**: `CMakeLists.txt` produces `ShadowrunRecomp.exe` from the framework's SDL runner (window 640x448, Direct3D11, 48 kHz audio, 59.94 fps pacing, rewind ring, feedback replay). Live keyboard/gamepad handling comes from that runner; the launcher UI (`recomp-ui`) is wired conditionally and not yet exercised. |
| **Save persistence on the SDL runner** | wired: `main.c` now calls `gbus_sram_set_always_mapped()` when the window lies beyond the ROM. Loading verified (`[SRAM] loaded 16384/16384 bytes`). An in-game **write** has not been reproduced on the SDL build yet — the scripted flow does not reach the save menu at the right frame. |
| **Validation scripts vs SDL build** | the SDL build is drivable with `--input-script` and captures its own screenshots, but its menu timing differs from the headless runner, so the scripted route is not calibrated yet. `scripts/validate*.ps1` still drive the headless harness; see `docs/SDL-FRONTEND.md` for the split and the proposed fix (RAM-state assertions instead of frame guessing). |
| Full-game coverage | verified through the first room and the save system, not the whole campaign |
| SDL/headless frame pairing | both builds show the same game, but an exact paired diff is blocked by the clock mismatch described in `docs/VALIDATION-REPORT.md` |
| Audio gap check | no underrun test over a long play (headless writes a file, not a device) |
| Uninitialised reads | Dr. Memory runs under `-ignore_kernel` but crashes at teardown; only its live error stream is usable, and it reports only `___chkstk_ms` false positives |
| Widescreen / mods / netplay | not attempted |

## Build paths

| Path | Produces | Used by |
|---|---|---|
| `CMakeLists.txt` | `ShadowrunRecomp.exe` (SDL window, audio, input) | players, release |
| `scripts/build_runner.ps1` | `shadowrun_runner.exe` (headless) | `scripts/validate*.ps1` |

The CMake build pins `m68k-recomp-core` at `2445cd2` (the commit the headless port was
validated against); newer core commits emit hooks this runner version lacks.

## Audit results (2026-11-09)

A full re-check is recorded in [`docs/VALIDATION-REPORT.md`](docs/VALIDATION-REPORT.md).
Highlights:

* clean clone builds and runs (weak shims were needed - fixed);
* the recompiler is deterministic (35/35 files identical across runs);
* a wrong ROM is rejected with the expected CRC message;
* the `recomp-ui` launcher builds and starts;
* the SDL build survives 120 000 frames (peak 128.9 MB, clean exit);
* two upstream facts were corrected: issue #71 was already fixed on master
  (`a7e8c5ea`), and the framework must be pinned at that commit or later.

## Known differences from real hardware

| | This port | Reference (BizHawk) |
|---|---|---|
| colour | hardware DAC ladder `{0,49,87,119,146,174,206,255}` (verified against BlastEm) | naive `v × 34` |
| audio rate | 53 267 Hz native, optional 48 kHz resample (linear, −1.7 dB at 12–20 kHz) | device rate |
| frame counter | starts 4–5 frames earlier than a power-on emulator run | — |

## Bugs found in the framework (reported upstream)

* `return_capture` misclassifies prologue/epilogue-split routines — <https://github.com/mstan/m68k-recomp-core/issues/14>
* always-mapped SRAM — <https://github.com/mstan/segagenesisrecomp/issues/71>
  **withdrawn**: upstream implemented it in `a7e8c5ea` (2026-10-24), one day after
  the v0.1.2 release this port was built from. I posted a correction in the
  thread; the fix is to pin the framework forward, not to patch it.

The return-capture fix is carried in `patches/0001-return-capture.patch` (still
unfixed on `m68k-recomp-core` `main` as of 2026-11-09).
