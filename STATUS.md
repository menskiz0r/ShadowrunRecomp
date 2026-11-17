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

---

## Sound: YM2612 timer A implemented (2026-11-17)

The missing music was a backend gap, not a game-logic or timing problem: the runner's
YM2612 model implemented only timer B, while Shadowrun's sound driver runs its sequencer
from timer A. The driver polled the status register millions of times waiting for a flag
that could never be raised, and its music stopped once the initially queued track ran out.

Timer A is now modelled (registers $24/$25, $27 bits 0/2/4, status bit 0, period
(1024 - TA) * 1008 master cycles, following ymfm's formula). Reference replay FM thirds:
6570/6570/383/383 -> 6570/6570/6353/4127. Boot hashes, the combat replay and determinism
are unchanged.

Awaiting player confirmation on a live session.

## Session summary (2026-11-16)

### Fixed and validated

| defect | fix | validation |
|---|---|---|
| SEGA logo freeze (picture stuck, sim running) | codegen return-slot gating (patch 0002, upstream PR #18) | verified across boot/intro |
| hotel check-out did nothing | call-site return displacement handling (patch 0003, upstream PR #19) | lands in the room, frame-identical to the interpreter |
| shooting stall: muzzle sprite sticks, shots go inert, game hangs | the four "interior" dispatch addresses are actually blocks after an RTS reachable only via a stored pointer; they are now real function entries via `[functions].late_extra` (`0x00B3EE, 0x014E0A, 0x00AC4E, 0x00B49C, 0x00B07E, 0x00B38A`) | player-verified shooting no longer fails; replay of the failing 5042-frame session matches all inputs, scenes 139 -> 35, `interior_label_misses.toml` empty, boot hashes unchanged |

### Open: music lost after a scene change

Root cause traced end to end:

1. `$052E4E` is the sound handshake routine (only ROM code referencing `$A00036`).
2. The 68K deposits an incrementing sequence at Z80 `$0036` and reads back the driver's echo.
3. At the scene-change re-init (~frames 3382/3389) the recompiled build reads back `1C`
   where the interpreter reads `3F`; those mismatches make the game stop depositing.
4. The command stream then ends (recompiled: last command frame 3389; interpreter: 4995),
   so the music stops while SFX continue (FM peak drops 6570 -> 383, device underruns 0).

Ruled out with measurements: audio device/driver/buffer, DSR knobs, our own patches,
register-span batching, per-instruction timer guard, Z80 sync at bus writes, and Z80/68K
slice interleaving (8/32/128 slices). All recorded in `docs/VALIDATION-REPORT.md`.

Next step: watch the Z80-side write to `$0036` around frames 3380-3390 in both backends
(`GENESIS_Z80_WATCH=0036`) to identify which driver state produces the wrong echo.

### Tooling left in place

- `scripts/record-session.ps1` - records a live session (timeline, RAM ring, audio, replay)
- `scripts/replay-run.ps1` - replays a session headlessly in ~10 s with audio capture
- `scripts/label_session.py` - scene timeline and skip detection
- `tools/compare_sessions.py` - frame/RAM diff between two reproduced sessions
- co-sim extras: `z80mem`, `memchunks`, per-line Z80 log, Z80/68K write watchpoints,
  instruction trace with addresses, chunk-yield log, span switch
- patches/0001-0005 document every change and every dead end

Validated references: boot hashes 1000/2000/3000/6000 = `45E5/E29B/06B5/11C1`;
two paced runs bit-identical; full combat-session replay matches all 5042 inputs.
