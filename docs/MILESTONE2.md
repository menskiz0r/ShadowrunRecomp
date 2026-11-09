# Milestone 2 — execution harness, hardware stubs, interrupt model

Status: **steps 9–10 complete; step 11 implemented and unit-tested, not yet proven against
the game** (the boot deadlocks before it enables interrupts).

## What was added

| Area | Implementation |
|---|---|
| VDP state | 24 registers, 64 KB VRAM, CRAM/VSRAM, address latch, auto-increment, data/control ports |
| VDP status | vblank, odd-frame, VInt-pending, HInt-pending bits; pending flags acknowledged on read |
| Timing | 488 cycles/line, 262 lines/frame; line counter, frame counter, vblank window at line 224 |
| Interrupts | level 6 (VBlank, vector 30 → `$00022E`) and level 4 (HBlank, vector 28 → `$000228`) with exception frames (PC + SR pushed), `sr` masking, IE1/IE0 gating |
| Memory map | version register `$A10001` now reports a US/NTSC console (`0xA0`); controller ports return `0x7F`; byte-sized VDP accesses routed through the VDP model |

## Bugs found and fixed on the way

1. **`move.w sr,-(a7)` was translated as `c->d[7] = ...`**
   The emitter assumed every `move` from SR/CCR target was a data register, so the
   interrupt-style "save status register on the stack" sequence corrupted the stack. The
   game's VDP upload routines returned through garbage (`pc=$0C800000`). Fixed and now
   covered by tests.

2. **Hardware version register returned 0**
   `$A10001` reading 0 makes the console look like a Japanese machine; the cartridge is a
   US release, so the game legitimately entered its region-mismatch screen and hung. With
   `0xA0` the boot proceeds past the check.

## Test results

```
59 checks, 0 failures
```

New interrupt coverage:
* vblank flag raised when the line counter crosses 224,
* level-6 interrupt delivered when IE1 is set and the mask allows it,
* PC taken from vector 30, exception frame contains SR and the return address,
* no interrupt when IE1 is clear,
* no interrupt when `sr` masks level 6.

## Where the boot gets to now

```
dispatches=20000000  pc=000BDE  sr=2304  line=79
frames=6327  interrupts=0
vdp data=69960 ctrl=223 | io=52 z80=103 ym=0 sram=0
VDP regs: 06 74 30 3C 07 68 00 00 00 00 55 00 81 00 00 02 ...
```

The game:

* passes TMSS and the region check,
* sets up all 24 VDP registers (display enabled, `reg1=0x74`),
* uploads ~70 KB of VRAM through the data port,
* talks to the Z80 bus 103 times (sound driver handshake),
* and then stops at `$000BDE`:

```
000BD2  addq.w #1, $ffdf88
000BD8  move.w $fff9f6, d7
000BDE  cmp.w  $fff9ee, d7
000BE4  beq.b  $000BDE      <- never leaves
000BE6  move.w $fff9ee, $fff9f6
```

It waits for a RAM word (`$FFF9EE`) to change, and **no code in the ROM writes that word** —
the only two references are the read at `$0BE0` and the store at `$0BE8`. The 16-bit value
sits inside a 32-bit counter at `$FFF9EC` that the VBlank handler increments, so it would
only change after 65,536 frames.

Conclusion: the game is not supposed to be on this path at this point — i.e. there is an
**upstream divergence**, not a missing feature. Interrupts are implemented; the game simply
never enables `IE1` (reg0 bit 4 is 0 at every write we can see) because it deadlocks first.

## Next

1. Find the divergence: run the same ROM in a reference emulator with execution tracing from
   reset, and compare the first differing block (~100k dispatches in). The most likely
   suspects are VDP status details (FIFO/DMA-busy bits), the DMA behaviour of the VRAM
   upload, or a subtle flag bug in an instruction used by the init code.
2. Once the boot reaches the point where it sets `IE1`, the interrupt path is already in
   place and should start ticking the frame counter.

## Files

| Path | Role |
|---|---|
| `runtime/vdp.c` | VDP registers/status/VRAM + timing + interrupt delivery |
| `runtime/m68k.c` | memory map, EA, ALU, dispatch, fault reporting |
| `runtime/main.c` | harness: reset, dispatch loop, tick, statistics, VDP/register traces |
| `runtime/tests.c` | 59 checks including the interrupt model |
| `build.ps1` | regenerate + build harness and tests |
