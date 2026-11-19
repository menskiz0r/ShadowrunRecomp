Resolved on our side — audio is fully correct now, and I owe you a correction to my
previous comment.

**What was still wrong after v0.1.3 + timer A + the reload rule.** I had said the timer
interrupt needed gating "to PCM activity". That was wrong. This driver counts **every**
Z80 interrupt as one sequencer tick (IRQ vector is `LD ($003E),SP; RETI`, and the main loop
turns the stored SP into a tick counter at `$0040`). Gating to DAC writes still delivered
timer interrupts throughout the PCM scenes, and because timer A is left programmed at PCM
rates (7056/10080/6048 cycles), that fed the driver thousands of ticks per second: the drum
pattern raced and its track ended before the scene's death voices.

**What actually fixes it:** do not deliver timer interrupts to the Z80 at all for this
driver. The status *flag* still updates and is what the driver polls to pace DAC bytes, so
PCM (voices, drums) keeps streaming — verified 0 interrupts/frame with the DAC still moving
~10.5 bytes/frame.

**How it was verified.** I built an independent emulator as a reference — BlastEm 0.6.3 from
source, different 68K/Z80/YM2612/VDP implementations — patched for frame-accurate scripted
input and per-channel YM WAV output. With identical inputs from reset:

```
                    kick/s   snare/s   hats/s
blastem (YM only)    12.2      4.6       7.4
port, timer IRQs on  17.8      8.0       9.4
```

That ~45% excess drum activity disappeared once timer interrupts stopped being delivered,
and the player confirmed the drums are now the correct speed and the track lasts through
the scene. Both systems agree on music timing before input (14 s: 162 vs 162 ms, 18 s: 242
vs 244 ms).

**On the PR offer:** still happy to send the timer A model and the reload rule (both are
general OPN gaps: timer A was simply not implemented, and a load written with the flag reset
must adopt the new period). I would *not* include the interrupt-delivery change as-is —
"never deliver timer IRQs" is correct for this driver but is a per-game property, so it
probably belongs behind a game spec/option rather than as a default. If you have a preference
for where that switch should live, I'll shape the PR around it.

Replay note stands: containers from the previous SDK are rejected with `invalid startup SRAM
attachment`, so replay validation here was re-recorded.
