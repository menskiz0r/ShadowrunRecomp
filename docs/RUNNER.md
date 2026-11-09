# Framework runner — built and running (M4 in progress)

## What was achieved

The **real framework runtime** now builds with the MinGW toolchain and runs the
recompiled game headlessly:

```
shadowrun_runner.exe   3.65 MB
  framework: glue.c (scheduler, vblank service, dispatch accounting, RTE/split-call
             bookkeeping), genesis_vdp/bus/machine/raster_jobs/color_lut, z80 core,
             clean-room 68000 interpreter, fiber support
  game:      32 generated translation units + dispatch + layout + cycles
  adapter:   ROM load, GameSpec (entry point, identity, CRC), scanline sink, BMP dump
  stubs:     SDL audio/input surface, ym2612 (silent), replay/rollback subsystems
```

Run:

```
shadowrun_runner.exe "Shadowrun (U) [!].bin" 300 frame.bmp
→ after 300 frames: insns=1510985
```

It runs 3,600 frames without crashing; the game boots, programs all 24 VDP
registers (`reg1 = 0x74`, display enabled), and keeps executing.

## What it revealed

Even on the framework's own runtime the picture stays black:

```
VDP regs: 06 74 30 3C 07 68 00 00 00 00 55 03 81 00 00 02 01 00 00 FF FF 00 00 80
CRAM[0..7]: 000 000 000 000 000 000 000 000
```

**The palette is never loaded.** That is now confirmed on two independent
runtimes (our shim and the framework's), which rules out the runtime as the
cause. The game parks before its palette upload.

## How it was built

[`build_runner.ps1`](../build_runner.ps1) compiles ~45 framework files + 35
generated files + the adapter and links the exe. Notable integration points:

| Piece | Status |
|---|---|
| `glue_init` / `machine_init` | called by the adapter before the frame loop |
| `GameSpec` | provided by the adapter: `call_entry_point` (reset vector → `recomp_call_addr`), name, CRC32 |
| `genesis_stop_until_interrupt` | game-owned per the framework; adapter parks until vblank |
| Scanline sink | required — without it the VDP renders "for status only" and every frame is black |
| Missing subsystems | audio (ym2612), replay/rollback, netplay, SDL input — stubbed for a headless build |

## Next diagnostic steps

1. Determine where the guest is parked: enable the framework's yield log and dump
   the guest PP/pc, or sample the host call stack as before.
2. Check whether the boot path depends on the Z80 sound driver: our ym2612 is
   silent; the driver's handshake may be what the game waits on.
3. Cross-check against a reference emulator with the same frame count: confirm
   that a stock Genesis shows the Sega/title screen by frame ~300-600.
4. If the game is parked on a dispatch that was never translated, the framework's
   interpreter fallback should handle it — verify misses are being served and
   recorded (`dispatch_misses*.toml`).
