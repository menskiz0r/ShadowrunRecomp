# Status

> ## ⚠ WORK IN PROGRESS - NOT PLAYABLE
>
> This is a research port under active development, not a finished game. It boots,
> renders, plays audio and reaches the first room, but **there are known
> game-breaking defects**, including at least one hang and one crash. Do not treat
> it as playable end to end.

Last updated: 2026-11-14.

## Known issues (open)

| # | Symptom | Cause / state |
|---|---|---|
| 1 | **Firing breaks the game.** Ammo depletes, the shot animation never advances, the muzzle sprite stays on screen, and a second trigger pull does nothing. | Computed dispatch targets routines that live *inside* other functions: `interior_label_misses.toml` records `$00B3EE`, `$014E0A`, `$00AC4E`, `$00B49C` (object/combat state machines operating on `(a0)`; `$014E0A` touches the `$FFDD50` timer). The recompiler has no in-function dispatch entry for them, so those routines never run. Seeding them as standalone functions is **not** a fix: it splits their parent functions, and the resulting build loses all sound shortly after firing and crashes elsewhere. |
| 2 | **Start menu hangs in free roam.** | Not localised yet; likely the same class as #1 (a menu object's state routine is unreachable). |
| 3 | **Crash during dialogue** (seen 2026-11-14, not yet reproduced under a script). | Not localised. |
| 4 | **Sound: music lost after a skipped cutscene - FIXED (measured).** Root cause: `ym_timer_update()` flagged a YM2612 timer-B overflow when `now >= deadline`, where `now` comes from a line-relative Z80 stamp that carries the current instruction's overshoot. Two runs of identical Z80 code could land a few master cycles either side of the deadline, flipping the timer flag and the sound driver's branch (the driver then goes silent while the device keeps receiving samples - 0 underruns). Patch `0006-ym-timer-guard.patch` requires 64 master cycles (~8 us) past the deadline. On the cutscene-skip route FM last-third went **383 -> 4822** (interpreter: 2396), validated boot hashes are unchanged (frames 1000/2000/3000/6000 = 45E5/E29B/06B5/11C1) and two paced runs remain bit-identical. Awaiting a player session to confirm by ear. | | 5 | Real-time pacing + a real audio device can change game state between runs of the same build. | Measured: paced runs differ at frame 2400 (`0x316C...` vs `0x7D11...`); uncapped runs are reproducible. Investigated as the cause of #4 and ruled out - #4 also occurs with the audio device removed. |

## Fixed (with evidence)

| Area | Fix | Upstream |
|---|---|---|
| SEGA logo → title **freeze** (picture stopped while the game kept running) | `patches/0002-rts-return-slot.patch` - the `rts` emitter consumed saved-register pops as return slots, leaking 4 bytes per call | PR **#18** |
| Hotel terminal **check-out doing nothing** (Yes returned to the menu) | `patches/0003-call-site-return-slots.patch` - indirect calls now unwind the return slots the callee actually consumed (`$DA6A` pops two and `rts`s past both) | PR **#19** |
| Return-capture misclassification (truncated callers at `$052E4E`) | `patches/0001-return-capture.patch` | PR **#15** |

## What is verified

| Area | Evidence |
|---|---|
| Boot → title → intro → room | frame hashes; matches the validated build before the WIP experiments |
| Hotel terminal flow | scripted route ends in the room, matching the interpreter |
| Audio present | FM peak 7395, PSG peak 8182 (mixer capture) |
| 12 000-frame soak | no watchdog, no crash report |
| Co-simulation (recomp vs Tier-3 interpreter) | works: `-DSHADOWRUN_BUILD_COSIM=ON`; RAM identical over the measured windows |

## What is not done

| Area | Reality |
|---|---|
| Full-game coverage | verified through the first room only |
| Combat | **broken**, see issue 1 |
| Start menu | **hangs**, see issue 2 |
| Save/load on the SDL build | loading verified; an in-game write has not been reproduced on this build |
| Widescreen / netplay | not attempted |

