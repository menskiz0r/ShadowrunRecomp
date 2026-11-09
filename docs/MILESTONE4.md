# Milestone 4 — COMPLETE

The recompiled game boots, runs the SEGA sequence, and renders the **title screen** —
logo, copyright text, and the "PRESS START" prompt — from the generated code.

| Frame | What it shows |
|---|---|
| 300 | *SEGA boot screen* (screenshot not distributed: copyrighted game imagery) |
| 900 | *title fading in* (screenshot not distributed: copyrighted game imagery) |
| 1500 | *Shadowrun title screen* (screenshot not distributed: copyrighted game imagery) |
| 2000 | *PRESS START* (screenshot not distributed: copyrighted game imagery) |

## The two bugs that blocked it

Both were **code-generation defects**, found by building `GenesisRecomp` from source and
patching it:

### 1. Return-capture false positive truncated functions

`m68k_return_capture_is_unconditional` saw `movea.l (a7)+,a0` at the top of `$052E4E` and
declared it a "capture and take over" callee. But that routine pops the return address,
**sets up a normal frame** (`link`, `movem`, `sr`) and pushes the address straight back before
an ordinary `rts`. Callers were therefore emitted as:

```c
recomp_push_return(0x052EB6u);
RECOMP_CALL_NATIVE(func_052E4E);
g_rte_pending = 0; /* callee captured our return; handled here */
return;            /* <- the rest of the function never existed */
```

The caller's remaining body was dropped and the pushed return slot leaked **18 bytes per
call**. Fix (`return_capture.c`): a capture is only a takeover when the routine does not
immediately rebuild a frame or push to the stack — reject on `link`, `-(A7)` push, or `rts`
within the next few instructions.

### 2. MOVEM frame restores counted as skipped returns

`_sp_popped += 8` for `movem.l (A7)+` made a shared epilogue look like a multi-slot return
skip, so `rts` emitted `g_rte_pending = 2` instead of returning. Fix (`code_generator.c`):
frame restores do not feed the skip counter; only explicit SP adjustments and `MOVE (A7)+`
pops can skip a return.

## How it was verified

* Recompiler built from source: `port/build_recompiler.ps1` → `GenesisRecomp_fixed.exe`.
* `GENESIS_STRICT_JSR_STACK=1` no longer aborts on the `$052F00` chain (the only remaining
  reports are the deliberate captured-return frames, which are correct by design).
* Frame captures at 300 / 900 / 1500 / 2000 frames show the boot animation progressing into
  the title screen.

## The bug that kept everything black

Interrupts were enabled (`reg1 = 0x74`, VInt on) but the **handler never ran**:

```
before:  vblcount = 0 at every frame, CRAM all zero, 0 non-black scanlines
after:   vblcount = 30, 70, 130, 190 ...  CRAM = EC0 EA0 E80 ...  15,076 non-black lines at frame 300
```

The framework delivers vertical interrupts by calling **back into the game**:

```c
if (g_game_spec.call_vblank) g_game_spec.call_vblank();   /* glue.c, own_deliver_vint */
```

Our `GameSpec` left `call_vblank` / `call_hblank` NULL, so every VBlank was acknowledged and
then silently dropped. The game's handler — which loads palettes, ticks its frame counter and
builds the display list — never executed. The adapter now installs both:

```c
static void shadowrun_call_vblank(void) {
    uint32_t handler = m68k_read32(0x78) & 0xFFFFFFu;   /* level-6 autovector */
    recomp_call_addr(handler);
}
```

This was the single missing wire. Everything upstream of it (runner build, memory map, VDP,
dispatch, fibers) was already correct — which is why two independent runtimes showed the same
black screen: both were faithfully honouring a configuration that never ran the interrupt
handler.

## Current state

```
frame  300: insns=1,558,375  sr=2308  vblcount=93        SEGA lightning screen
frame  900: insns=4,066,242  sr=2308  vblcount=...       SEGA logo
frame 1700: insns=...        ~28 s of game time          transition frame
frame 1715: CRASH REPORT — watchdog: 10,000,000 bus accesses without yield
```

So the boot sequence runs, the display list is built, palettes are loaded and frames are
rasterised. At ~frame 1715 the guest enters a tight poll loop that never reaches a yield
point and the framework's runaway watchdog stops it.

## The stall at frame ~1715 — diagnosed

The watchdog fires inside the **VBlank handler**, not in a poll loop:

```
CRASH REPORT  frame=1715  reason: instruction watchdog: 20000000 native insns without yielding
Last access: READ $000000
Registers:
  D0=$00110193 D1=$00110000 D2=$0000FFFE D3=$311E0000
  D4=$00000001 D5=$00160001 D6=$01190010 D7=$01600D91
  A0=$00009AF0 A1=$00C00000 A2=$0001D538 A3=$00FFD9CE
  A4=$FFFF00FF A5=$BAC00000 A6=$00160001 A7=$00FFFF92 (SP)
  SR=$2700
Stack walk (A7=$FFFF92):
  [SP+$00E] $000F92   [SP+$01E] $00618E   [SP+$022] $0018FE   [SP+$026] $00107A
```

Facts:

* `SR=$2700` — interrupts masked, so this is code running **inside** the handler.
* `$00107A` is the instruction right after `jsr $1872` in the VBlank handler, so the walk is
  genuine: `0x1070 → 0x1872 → … → 0x0618E → 0x00F92`.
* `A1=$00C00000` (VDP data port) and `A0=$00009AF0` (a ROM pointer) — this is a graphics
  transfer/decompression loop feeding VRAM.
* **Last access: READ $000000** — the source pointer has wrapped to address 0, and the loop
  never reaches its terminator.

So the handler enters a decompression/copy routine whose end condition never becomes true;
the pointer ends up at $000000 and it spins forever. This is the first real translation-level
defect (not a wiring problem) and it is exactly the kind of thing the framework's differential
co-simulation is designed to localise.

## The loop, traced

The stack walk leads to a **sprite/tile list walker**:

```
006148  move.w  $ffdf2a,d7        ; sprite count
00614E  move.w  d7,d0
006150  subq.w  #1,d7
006152  move.l  $ffdf2c,d1        ; list base
006158  lsl.b   #2,d0
00615A  sub.b   d0,d1
00615C  movea.l d1,a1
00615E  movea.l (a1),a0           ; sprite record pointer
006160  move.l  $22(a0),d0
006172  btst.b  #5,$11(a0)
006180  move.w  $26(a0),d1
006184  move.w  $28(a0),d2        ; <-- length field
006188  jsr     $f5c              ; -> 0xf98: copy (a0)+ -> VDP, d2>>6 blocks
00618E  move.l  a1,d0
006190  addq.b  #4,d0
006192  movea.l d0,a1
006194  dbra    d7,$615e
006198  clr.w   $ffdf2a           ; count reset only after the walk
```

Two things are wrong at the crash:

* **The count is 0x0D91 (3473) and still growing** — it is incremented at `$006140`
  (`addq.w #1,$ffdf2a`) and only cleared at `$006198`, *after* the walk. Because the walk
  never completes, the count grows by ~2 per frame (1700 frames → 3473).
* **Each record yields `d2 = 0xFFFE`**, i.e. `d2 >> 6 = 1023` blocks of 64 bytes → a 64 KB
  copy per sprite. The copy routine itself is translated correctly (`lsr.w #6`, `subq.w`,
  `bmi`, `dbra` all verified in the generated C), so the bad value is the record field at
  `$28(a0)` — meaning `a0` (the record pointer) is wrong, or the list base `$FFDF2C` is.

Net effect: 3473 × 64 KB ≈ 227 MB of VDP copies → ~56 M instructions inside one handler →
watchdog.

## Next

1. Trace who pushes records onto the list (`$006140` callers) and why `$FFDF2C`/record
   `+$28` read garbage — compare with Musashi at the first frame the list is non-empty.
2. Either a pointer in RAM is being computed wrongly (translator defect), or the game is
   queueing objects that should have been rejected earlier.
3. Once the walk terminates, the count clears, the title should draw — then compare against a
   reference emulator.

## Reproduce

```
build_runner.ps1
shadowrun_runner.exe "Shadowrun (U) [!].bin" 900 frame.bmp
```
