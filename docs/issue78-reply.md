Thanks — v0.1.3 integrated cleanly, and its "preserve the running timer's phase"
rule was directly useful. It took three changes on our side to get Shadowrun's audio
right, two of them in the shared backend.

**1. Timer A was not modelled at all.** Instrumenting the status path showed the Z80
polling the YM status register millions of times with the overflow flag never set
(`timer-B flag seen: 0`). The register log showed why:

```
[YMREG] f=227  reg=27 val=05     ; bit0 load timer A, bit2 enable
[YMREG] f=2749 reg=24 val=FE     ; timer A period (TA=1017 -> 7 * 1008 = 7056
[YMREG] f=2749 reg=25 val=01     ;   master cycles = 7609 Hz, a PCM rate)
[YMREG] f=2749 reg=27 val=55     ; load + enable + reset flag
```

`runner/video/genesis_bus.c` implemented only timer B (the comment "only timer flag B is
currently needed by supported software" is true for the Sonic titles, not for this game).
We added timer A following `ymfm_fm.ipp` - `(1024 - TA) * 144` chip clocks, i.e.
`(1024 - TA) * 1008` master cycles at the same 7:1 scale the file already uses for timer
B's 16128 - with `$24`/`$25`, `$27` bit 0 load / bit 2 enable / bit 4 reset, and status
bit 0.

**2. A reload while running needs to adopt the new period.** Shadowrun runs the intro at
TA=0 (52 Hz) and switches to 7056 cycles when it starts streaming PCM, writing
`$27 = $55` (load *and* reset) each time. Our first version of the "preserve the phase"
rule (yours, which correctly stops acknowledgements from restarting the timer) also
ignored that re-programming, so the PCM rate never took effect. Our rule is now: a load
that also resets the flag, or that carries a changed `$24`/`$25`, restarts with the new
period; a plain acknowledgement still preserves the phase.

**3. The timer interrupt has to be gated to PCM activity.** This driver's IRQ vector is
six bytes - `LD ($003E),SP; RETI` - and the main loop treats each interrupt as one tick
by watching that stored SP. Delivering an interrupt per PCM sample therefore also drove
its pattern/music clock (in-game FM note rate went 6.5/s -> 17.5/s, and stayed fast
because the driver leaves timer A at a PCM rate afterwards). We now deliver the timer
interrupt only while the driver is actually writing DAC bytes, and the FM note rate is
back at 9.7/s with the DAC stream running at ~5200 bytes/s.

Result for us: FM music, drums, the chopper and the death voices all play, at the original
tempo for regular music.

Still open (not your fix, just our remaining bug): the drum pattern in the ambush runs
fast. Halving the interrupt rate changes nothing, so it is not interrupt-driven - we are
reading the uploaded Z80 driver (it lives in Z80 RAM, not ROM) to find its pattern
counter.

**Replay format note:** containers recorded with the previous SDK are rejected with
`invalid startup SRAM attachment`; we re-record for replay validation. Not a complaint,
just so the message is not mistaken for a bug in the new format.

The timer A support is small and self-contained (bus model + size guards in
`rb_state.c`). Happy to send it as a PR if it is useful to you - it is a general OPN gap,
not Shadowrun-specific.
