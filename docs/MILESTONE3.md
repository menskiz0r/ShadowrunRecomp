# Milestone 3 — runtime drives the game ✅

The generated game code now runs inside a working runtime. It boots past reset, initialises
the VDP, and keeps executing frame after frame without crashing.

## Evidence

```
ROM: Shadowrun (U) [!].bin (2097152 bytes, crc32 FBB92909)
reset: pc=000236 sp=00FFFFF8
  frame  300: insns= 1227330 a7=00FFFCA2 reg1=74 vdp[data=138068 ctrl=508]
  frame  600: insns= 2012778 a7=00FFF5AC reg1=74 vdp[data=226324 ctrl=902]
  frame  900: insns= 2789014 a7=00FFEEB6 reg1=74 vdp[data=315028 ctrl=1298]
  frame 1200: insns= 3565423 a7=00FFE7C0 reg1=74 vdp[data=403732 ctrl=1694]

frames=1200  insns=3565423
VDP regs: 06 74 30 3C 07 68 00 00 00 00 55 03 81 00 00 02
```

* **1,200 frames** (~20 s of game time), 3.57 million guest instructions, no crash.
* VDP register 1 = `0x74` → **display enabled**.
* Register 10 changes `0x55 → 0x03` → the game reprograms the H-int counter, i.e. it is
  configuring interrupts for the next phase (it ran the boot/init path, not a hang).
* 403,732 data-port writes and 1,694 control-port writes accumulated — the game is feeding
  VRAM continuously.

## What was broken and fixed

| Bug | Symptom | Fix |
|---|---|---|
| `g_rte_pending_ptr` left NULL | SIGSEGV in `recomp_drain_tailcalls` on the first RTE check (the header defines `g_rte_pending` as `(*g_rte_pending_ptr)`) | point it at real storage |
| VDP status byte order | 8-bit reads of `$C00004/5` returned the high byte for both ports, so polls never saw the vblank bit | map byte offset correctly (high byte at `$C00004`, low at `$C00005`) |
| No frame budget | the guest loop is infinite by design, so the harness never reported anything | `DSH_FRAMES=N` stops after N frames and prints state; `DSH_VERBOSE=N` logs every N frames |

## Known issue: guest stack drift — diagnosed

`A7` drifts downward monotonically: `00FFFD20 → 00FFE7C0` over 1,200 frames (~4.5 B/frame).
It is a real leak, not deeper nesting. The framework's own strict checker localises it:

```
GENESIS_STRICT_JSR_STACK=1 →
JSR stack mismatch at $052F00 -> $052EB0: pre=$00FFFFD4 slot=$00FFFFD0 post=$00FFFFBE
```

The call site is the classic "callee captures the return address" split pattern:

```
052EFE  move.l d0,-(a7)      ; push argument
052F00  jsr    $52EB0        ; callee
052EB0  recomp_push_return(0x052EB6)   ; generated: callee captures return
        ...                            ; returns without popping
```

The generated code is written against the framework's glue, which accounts for these
split/tail-call frames (`g_split_sp_popped`, `g_rte_pending`, `recomp_tail_frame`). Our
300-line shim implements a simplified version, so each such call loses a few bytes.

**Therefore:** the drift is not a bug in the game code or the translator — it is the
expected consequence of running generated code on an approximate runtime. Fixing it properly
means using the framework's real glue (`runner/glue.c`), which compiles standalone with
MinGW (`glue.o`, 55 KB) but needs its companions (`fiber_compat.c`, `m68k_interp.c`,
`gbus`, `runtime_evidence.c`, `crash_report.c`, host helpers) linked in.

Until then: safe for short runs (thousands of frames); not safe for long play sessions.

## Reproduce

```powershell
$env:DSH_FRAMES='1200'
$env:DSH_VERBOSE='300'
build\shadowrun_runner.exe "<your Shadowrun (U) [!].bin>" 1200 frame.bmp
```

## Next

M4 — draw something. `vdp_render_frame()` is still a stub; the VDP has VRAM, CRAM, VSRAM and
registers, and the game is filling them, so the work is the rasteriser: planes A/B, window,
sprites, scrolling, palettes, then compare frames against a reference emulator.
