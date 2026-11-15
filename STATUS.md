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
| 4 | **Sound: music lost after a skipped cutscene - OPEN.** A 64-cycle guard on the YM2612 timer-B deadline (patch 0006) was measured against a scripted skip route and appeared to fix it (FM last-third 383 -> 4822), but a live session pressing at different frames still ended at **383**, and the change has been reverted as unvalidated. Root-cause analysis stands: the timer status read is stamped from a line-relative Z80 value carrying instruction overshoot, so a few-cycle difference can flip the driver's branch; the guard simply moved the threshold rather than removing the sensitivity. | 
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

### Combat / shooting (fixed 2026-11-16)

Shooting stalled because the game jumps through stored code pointers to blocks that
no scanned function covered (`$00B3EE` follows an `RTS` at `$00B3EC`). Those blocks,
plus two more found after the first fix (`$00B07E`, `$00B38A`), are now emitted as
function entries via `[functions].late_extra`. Validated against the recorded
5042-frame combat session: all inputs replay, `interior_label_misses.toml` is empty,
scenes drop from 139 to 35, and the boot hashes are unchanged.
