Thanks — v0.1.3 integrated cleanly, and it turned out there were two independent
problems on our side. One is what you fixed; the other is a backend gap we had to fill
for this game.

**What you fixed applies to us too.** We moved the port from `48e0f90` to `v0.1.3` and
carried the "preserve running timer phase when clearing its flag" rule into the timer we
added (see below): previously every load/acknowledge restarted the deadline.

**The larger issue: timer A is not modelled at all.** Instrumenting the YM status path
showed the Z80 polling the status register millions of times with the overflow flag
never set (`timer-B flag seen: 0`). Logging the timer programming showed why:

```
[YMREG] f=227  reg=27 val=05     ; bit0 load timer A, bit2 enable timer A flag
[YMREG] f=1628 reg=24 val=FE     ; timer A period
[YMREG] f=1628 reg=25 val=01
[YMREG] f=1628 reg=27 val=55     ; load + enable + reset A flag
```

Shadowrun's driver runs its sequencer from **timer A**; `runner/video/genesis_bus.c`
implemented only timer B (the comment "only timer flag B is currently needed by
supported software" holds for the Sonic titles, not for this game). The sequencer played
the initial track and then stopped once nothing advanced it.

We implemented timer A following `ymfm_fm.ipp` (`period = (1024 - TA) * OPERATORS *
clock_prescale`, i.e. `(1024 - TA) * 1008` master cycles at the 7:1 master/YM scale the
file already uses for timer B's 16128 constant): registers `$24`/`$25`, `$27` bit 0
load/run, bit 2 flag enable, bit 4 flag reset, status bit 0, plus the phase-preservation
rule from `18921ed`.

**Result** (pre-resample FM capture, thirds of the run):

```
before: 6570 / 6570 /  383 /  383      music dies in the first third
after : 6570 / 6570 / 4822 / 4566      music continuous
```

Boot hashes for frames 1000-6000 are unchanged by the timer change, and two paced runs
produce bit-identical audio.

**One format note:** replay containers recorded with the previous SDK are now rejected
with `invalid startup SRAM attachment`, so we re-record for replay-based validation. Not
a complaint, just so you know the error text can come from an older recording.

**Separate, unrelated:** the intro cutscene pacing still differs between our recompiled
build and our own interpreter (at matched game VBlank counts, cutscene screens advance
differently). We don't believe that is the sound timer; we're treating it separately.

If you want, the timer A support is small and self-contained and we'd be glad to send it
as a PR — it's a general OPN gap, not Shadowrun-specific.
