# Validation report

Date: 2026-11-09. Everything below was executed on this machine; nothing is
inferred from the code.

## Build reproducibility

| Check | Command | Result |
|---|---|---|
| Clean clone builds | fresh `segagenesisrecomp` clone (master) + this repo + `patches/0001` | **PASS** - `ShadowrunRecomp.exe` 8 875 170 bytes, runs (window, D3D11, audio, pacing) |
| Clean clone without the patch | — | not tested; the patch fixes a proven codegen bug (`issues/14`) |
| Generator determinism | recompiler run twice into separate directories | **PASS** - 35/35 files identical (only the output-path banner differs) |
| Wrong ROM rejected | ROM with one byte flipped | **PASS** - `ROM identity mismatch: CRC32=AE9D5A79, expected=FBB92909. Refusing to execute address-specific recompiled code.` |
| Launcher (recomp-ui) | CMake with `recomp-ui/` present | **PASS** - `recomp-ui: launcher enabled`, builds, and the binary starts the launcher (`[launcher] SDL runtime 2.28.5 ...`) |

Fix required during this audit: the `GameSpec` shims (`glue_sr_written`,
`genesis_stop_until_interrupt`) collided with the newer framework, which defines
them itself. Both are now `__attribute__((weak))`, so a framework definition wins
and an older framework still links.

## Headless harness (deterministic)

| Check | Result |
|---|---|
| `validate.ps1` (8 checks) | **PASS** - boot, no-leak, empty coverage evidence, save round trip, rendering |
| `validate-saves.ps1` (14 checks) | **PASS** - missing/truncated/oversized/garbage `.srm`, slot 2, kill mid-run |
| 300 000-frame soak | **PASS** - 34-40 M instructions, no crash, RSS decelerating 9.3 -> 12.7 MB |
| Leak counter | **PASS** - live-block delta constant at 31 across 3 k-40 k frames |
| Frame comparison vs BizHawk | **PASS** - 100 % structural at aligned checkpoints |
| Dr. Memory | runs under `-ignore_kernel`, 0 errors after suppressing `___chkstk_ms`, crashes at teardown |

## SDL front-end (playable build)

| Check | Result |
|---|---|
| Window, renderer, audio, pacing | **PASS** - `640x448`, D3D11, 48 kHz, 59.94 fps |
| Runs the real game | **PASS** - self-captured screenshots of the SEGA screen, intro, hotel dialogue, Pocket Secretary, character sheet |
| 120 000-frame soak | **PASS** - 198 s at 609 fps uncapped, peak working set **128.9 MB**, clean exit, benchmark digest emitted |
| Scripted input | **PASS** - `--input-script` with `WAIT`/`PRESS`/`SCREENSHOT`/`DUMP_RAM`/`EXIT` |
| State-keyed waits | **PASS** - `WAIT_RAM8 FFE231 0` blocks until the Pocket Secretary is up |
| Menu state ids | mapped in `$FFE2xx` (`FFE231` hotel=2/PS=0, `FFE241`, `FFE245`, `FFE24A`, `FFE267`) |
| Frame diff vs headless | **NOT DONE** - screenshots from both builds show the same game, but an exact paired diff is blocked by the clock mismatch below |
| Scripted save | **NOT DONE** - see below |

### Why the SDL route is not scripted end-to-end

`input_script` advances **once per wall frame**; the game consumes **simulated
frames**. Measured divergence on the same script:

| Mode | Scripted checkpoint | Simulated frame | Error |
|---|---|---|---|
| uncapped | 21 400 | 21 401 | -300 (early) |
| real speed | 21 400 | 22 301 | +900 (late) |

Screenshots at real speed are black until the simulation catches up, which is why
the SDL/headless frame pairing could not be produced. The save is proven on the
headless build (14/14).

### Attempts to get a reliable state key (negative results, recorded)

`DUMP_RAM` works: the dumps contain real game data (the player name "Joshua" is
present at the expected area), so the tooling is sound.

1. **`$FFE2xx` block** - first candidates (`FFE231`, `FFE241`, `FFE245`, `FFE24A`,
   `FFE267`), chosen because they differed between two menu states. **Rejected**:
   `FFE231 == 2` turned out to be true in both the hotel menu *and* the Pocket
   Secretary on different runs, so they are not state ids.
2. **`$FFF0D0`** - the top-level mode byte. Found statically in the dispatcher at
   `$11740` (`cmpi.b #$2,$fff0d0` / `move.b $fff0d0,d1` / index into the 18-byte
   record table at `$d1d28`, and the menu-target table at `$d2a0a`). **Rejected for
   this purpose**: it reads 0 in every captured menu state, so it selects a
   *top-level* mode (title/map), not the in-game menu currently on screen.

3. **`$FFF0D0` as a subsystem gate** - the new `DSH_DUMPRAM` hook in the headless
   adapter made the mapping measurable on the deterministic build:

   | frame | mode | screen |
   |---|---|---|
   | 1 000 - 12 000 | 0 | boot, title, menus, archetype, intro, room |
   | 18 000 | 1 | status panel |
   | 20 000 - 23 200 | 6 | Pocket Secretary / save subsystem |

   `$FFF0DC` (`sel`) is a second useful signal: 1 while a dialogue is up, 0 after.

   **So the gate exists, but only past the front-end.** Ported to the SDL build,
   both `WAIT_RAM8 FFF0D0 1` and `WAIT_RAM8 FFF0DC 1` never fired: the SDL run does
   not reach the same game state at all, because the *early* route (title -> menu
   -> archetype -> intro) is still frame-timed, and that is exactly where the two
   builds diverge. Mode is 0 through the whole front-end, so it cannot gate those
   steps.

Conclusion: automating the SDL route from the start needs state variables for the
**front-end** screens, which have not been identified. That is a larger
reverse-engineering task (find what the title/menu/archetype code tests), not a
tuning problem - three separate attempts with state gates all blocked on it.

## 2026-11-13: the SDL build freezes after the logo - NARROWED

Symptom: the window shows the SEGA logo animation, then the picture reverts to the
boot image and never changes again.

Measured with `--hash-frames` (FNV-1a-64 of the framebuffer), cross-checked against
the validated headless build's BMPs hashed the same way:

| frame | native (recompiled) | interpreter (`GENESIS_FORCE_INTERP=1`) | headless reference |
|---|---|---|---|
| 200 | `0x635CB0B6...` | `0x635CB0B6...` | `0x635CB0B6...` |
| 240 | `0x2A0B9729...` (boot image) | changes | changes |
| 400 | `0x2A0B9729...` (frozen) | `0x1AF74A08...` | changes |

So:

* the config, the ROM and the port are fine - the **interpreter runs the same frames
  as the validated headless build** (frame 600 matched exactly during a longer run);
* the **recompiled** path diverges at the logo-to-title transition and freezes;
* no dispatch misses, no floor entries, no crash report - it is a *mis-executed*
  path inside generated code, not a missing one.

Ruled out along the way (each tested, not assumed): the framework commit (old
`2445cd2` freezes identically), pacing mode (`fiber` and `accurate` both freeze),
the STOP handler (a no-op variant freezes identically), renderer driver (software,
opengl, direct3d, direct3d11 all black in screenshots), the GameSpec body (mirroring
the working headless adapter changes nothing), and the interpreter floor
(`GENESIS_FLOOR=1` finds nothing to interpret).

Playable workaround today:

```powershell
$env:GENESIS_FORCE_INTERP = '1'
build\ShadowrunRecomp.exe shadowrun.bin
```

Slower (interpreted), but it runs the game: with `--hash-frames` the interpreter
produces a new frame every sample (200/400/.../1800 all differ, and frame 600
matches the validated headless build byte-for-byte). `play.bat` next to the exe
sets this for you.

The native path still stalls on the boot image after the logo, with occasional
partial redraws. Ruled out so far (each tested): the framework commit, pacing mode,
the STOP handler, the renderer, the GameSpec body, the interpreter floor, and the
`vblank_yield_addr` replacement (disabling it changes timing but does not unstick
the loop). The remaining difference is in generated code around the logo-to-title
transition and needs the co-sim target (`GENESIS_COSIM`, `docs/COSIM.md`, pairing #1
recomp-vs-interp) to name the offending routine; that target is not built by this
CMakeLists yet.

### 2026-11-13 (later): the picture freezes, the game does not

Adding the VDP display bit and reading the per-frame RAM hash in the frame log
corrected the diagnosis:

* the **work-RAM hash changes every frame** through the freeze (frames 225-260
  all differ), so the game logic keeps running;
* the **framebuffer** stops changing and stays on the SEGA-logo image;
* `genesis_vdp.c` skips row rendering entirely while the display is disabled
  (`if (!gvdp_display_enabled(v)) return;`), so a disabled display explains a
  frozen picture with a live simulation;
* VRAM at frame 240 differs from the interpreter's in 296 bytes, in a
  small table at VRAM $0000-$0FFF (values 0-31, stride 4).

So this is a *rendering* divergence, not a hang. The recompiled code and the
interpreter disagree about what the game wrote to the VDP between frames ~230
and ~240.

Getting the PC needs the co-sim target (`docs/COSIM.md`, pairing #1). A
`SHADOWRUN_BUILD_COSIM` option was added to `CMakeLists.txt`, but it does not link
yet: `m68k_interp.c` needs `game_insn_cost()`, which comes from a per-game
instruction-cost table (`<prefix>_cycles.c`) that this project does not generate.
Producing that table is the prerequisite for the co-sim build.

### Co-simulation is now built and running (2026-11-13)

`-DSHADOWRUN_BUILD_COSIM=ON` produces `ShadowrunRecomp_cosim.exe`. Two fixes were
needed against the framework's helper:

1. the per-instruction cost table (`<prefix>_cycles.c`) is written by the
   recompiler to `generation-stage/<prefix>/` and **never copied into
   `generated/`**, so the co-sim target must reference the staging path;
2. the co-sim target needs `runner/game_cycles.c` (defines `game_insn_cost`) and
   `runner/frame_snapshots.c` (defines `m68k_snapshot`), neither of which the
   generated-sources helper adds.

Run with the framework's own scorecard (full output in `docs/cosim-report.txt`):

```powershell
python segagenesisrecomp/tools/divergence_report.py ^
  --game-config cosim_cfg.json --frames 400 --no-oracle --cycles 2000000
```

Result at 2 000 000 cycles:

| subsystem | verdict |
|---|---|
| ram, z80, z80ram, handshake, fm, psg, evq | **bit-exact** |
| cpu68k, timing | split at cp 1322 |
| vdp | split at cp 1363 (92.7 %) |

Drilling the CPU split: at cp 1322 the only differences are `sr` `2700` vs `2704`
(the Z flag) and `d7` `0x3CEB` vs `0x3CEC`, inside the boot delay loop at
`$073A` (`move.w #$FFF,d7 / nop / dbra d7,$73E`). That is a *phase* difference of
one loop iteration at a fixed cycle checkpoint, not a wrong result - consistent
with RAM being bit-exact.

So: the recompiled code produces the same game state as the interpreter. The
frozen picture is therefore in the rendering/present path, not in the translated
game logic, and the next measurement is the VDP split at cp 1363.

### Frame-scale co-simulation: first real divergence is a 4-byte stack imbalance

The 2 000 000-cycle run above covers only ~0.2 frames, so it never reaches the
freeze. Re-running at a 10 000-cycle stride finds the first real RAM divergence at
**cp 327 (~3.27 M cycles)**:

| | A (recompiled) | B (interpreter) |
|---|---|---|
| a7 | `$00FFFFAE` | `$00FFFFB2` |
| B's PC | - | `$052E7E` |

A7 is exactly one longword lower in the recompiled run, and the interpreter is
inside the captured-return routine at `$052E4E` (its prologue pops the return into
A0, pushes a frame and pushes the return back before its `rts` at `$052E82`).

That routine is the one the `0001-return-capture` patch changed the classification
of. Generated callers such as `func_052EB0` now emit the ordinary call form:

```c
recomp_push_return(0x052EB6u);      /* JSR push */
RECOMP_CALL_NATIVE(func_052E4E);
```

while the callee unconditionally consumes that pushed slot. So the caller and the
callee disagree about who owns the return slot - a four-byte drift that starts on
the very first call and accumulates.

Next experiment: force `m68k_return_capture_is_unconditional` back to "capture" for
this site and re-run the co-sim at cp 327. If A7 then matches, the patch needs a
third classification (`capture-and-continue`: push, call, **no pop, fall through**)
instead of its current two-way choice.

### The logo freeze is fixed (2026-11-13)

Root cause found with the co-simulation, not by guessing: the `rts` emitter in
`code_generator.c` treated `_sp_popped >= 4` as "the callee already popped the
return address". `_sp_popped` counts every `(SP)+`, including ordinary saved
register restores, so any function whose epilogue is

```
move.w (s7)+,d0
move.w (s7)+,sr
rts
```

made its caller skip the return-slot pop - a four-byte stack leak per call.
`$0E34` (the VDP control-port setter called from `$0C88`) is exactly that shape.

Evidence trail:

* co-sim cp 327 (~3.27 M cycles): A7 `$00FFFFAE` vs `$00FFFFB2`;
* co-sim cp 3068: A7 `$00FFFFE4` vs `$00FFFFEE`, D1 `$00000000` vs `$0000FFFF`,
  interp at PC `$052E7E`;
* cp 61378 (50-cycle stride): split while the interpreter sat at `$0C88`
  (`bsr.w $0E34`);
* generated `func_000E9C` showed the bad `rts` emission verbatim.

Fix: `patches/0002-rts-return-slot.patch` - a callee may consume its return slot
only when it is **proven** to capture the return, or when it skips SP through an
explicit `ADDQ/SUBQ` (the SMPS stop-track pattern). A/B check: forcing the old
classification gave an A7 error of `0x4E`; the patch gives exact agreement.

After the fix, through 3 M cycles the co-sim reports A7, D1 and RAM **identical**
at every checkpoint. On screen the SEGA logo now hands over to the title instead
of freezing, and audio is audible.

The frame-1717 watchdog stall and the low audio level reported just after the fix
were **stale generated code**: the earlier A/B build had left capture-classified
callers in `generated/`, and the regeneration stamp kept them. After a clean
`build/` wipe and full rebuild:

| check | result |
|---|---|
| 12 000-frame run | no crash report, no watchdog |
| framebuffer | new hash every 2000 frames, through 12 000 |
| FM peak (mixer, pre-DRC) | 7395 (interpreter reference 7529) |
| PSG peak | 8182 (was 0) |
| frame 5000 | `0x5F8D68D6...`, the validated build's title-screen frame |

Lesson recorded: a `generated/` wipe is not enough; a stale generation stamp
survives it and re-uses old output. Wipe the whole `build/` directory when the
recompiler itself changes.

### The residual co-sim splits are cycle phase, not defects

After patch 0002 the co-sim still reports `cpu68k`/`timing` splits at cycle
checkpoints (e.g. cp 3068: A7 `$00FFFFE4` vs `$00FFFFEE`, SR `2704` vs `2700`).
Sampling around one of them shows both reconverge:

| checkpoint | A7 | SR |
|---|---|---|
| 3000 | same | same |
| 3068 | diff | diff |
| 3100 | **same** | **same** |
| 3300-4000 | same | diff |
| 4200 | same | **same** |
| 4500 | same | same |

A leaked return slot never heals; this does. The two backends simply sit at
slightly different instruction boundaries at the same guest cycle, because their
per-instruction cycle charges differ by a cycle or two (`timingfields` showed
`audio_cyc` 90638 vs 90640 at an identical `master_cycle`). Confirming evidence:

* strict JSR stack checker (`GENESIS_STRICT_JSR_STACK=1`): zero mismatches over 500 frames;
* 12 000-frame run: no crash report, no watchdog, new framebuffer hash throughout;
* frame 5000 renders the validated title frame `0x5F8D68D6...`;
* FM peak 7395 (interpreter 7529), PSG 8182.

So pairing #1's remaining signal is timing-model granularity, not a translation
bug. Making it exact would mean matching the interpreter's cycle charges
instruction-for-instruction - cosmetic for gameplay, and the game-level evidence
above is the accepted gate.

### Hotel check-out confirm: open, reproducible, intermittent in play

Symptom (manual play): at the hotel terminal, **Check Out** is highlighted, A opens
"Do you wish to check out?", moving to **Yes** and confirming sometimes puts the
player in the room (correct) and sometimes drops back to the Hotel Options menu.

A deterministic reproduction exists (`scripts/route-user.input`, native vs
`scripts/route-user-i.input`, interpreter). Both are driven with the identical
script: START at login, A on New Game, A on Samurai, START to skip the intro, five
A presses to the menu, DOWN to Check Out, A, UP to Yes, A.

The two backends are pixel-identical at every step up to the confirm:

| step | native vs interpreter (mean abs diff) |
|---|---|
| Hotel Options | 0.32 |
| cursor on Check Out | 0.13 |
| "Do you wish to check out?" | 0.33 |
| cursor on Yes | 0.38 |
| **after A on Yes** | **38.13** |

The interpreter closes the terminal and leaves the player standing in the room;
the recompiled build returns to the menu with the cursor reset to Karma Screen.

So the divergence is in the confirm handler, and it is timing-sensitive: with
scripted input (same frame every run) the recompiled build fails every time, while
manual play sometimes passes because the press lands on a different frame.

`game.toml` carried `vint_routine = 0x00F9F0`, set during an earlier experiment.
That address is *cleared* by the VInt handler, so it is not a "routine byte" and
`glue_yield_for_vblank()` wrongly treated waits as already satisfied. It is back to
0 (always park), which is the correct default for this title and changes frame
yield timing - the most likely reason the bug presents intermittently.

Regression after the change: 12 000 frames, no crash report or watchdog, FM peak
7395, PSG peak 8182, framebuffer hash advancing throughout.

### Check-out confirm: root cause identified (fix still open)

The hotel terminal's menu loop (`$0CF82`) calls the selected entry through a jump
table at `$C14C8`:

```
CFC6  btst.b  #$e,$ffdd22     ; A pressed?
CFCE  beq     $cfea
CFD2  lea.l   $c14c8,a0
CFD8  bsr.w   $c436           ; dispatch
CFDC  tst.b   $fff0dc
CFE2  bmi.w   $cffc           ; negative -> leave the terminal
CFE6  bra.w   $cf4e
```

`$C436` reads `$FFF0DC`, shifts it left twice and does `jsr (a0)` on the table
entry. Entry 1 is the Check Out handler at `$DA6A`, whose prompt loop ends with:

```
DB12  tst.b   $fff0dc        ; 0 = Yes, 1 = No
DB18  bne     $db24          ; No -> ordinary rts
DB1C  move.l  (a7)+,d0       ; Yes: pop the handler's return ...
DB1E  move.l  (a7)+,d0       ; ... and the dispatcher's return
DB20  move.w  #$ffff,d6      ; signal "checked out"
DB24  rts                    ; returns past both
```

**That is a legitimate return capture**: pop two longwords, then `rts` returns to
the menu loop's caller with `d6 = -1`. Patch 0001 (`patches/0001-return-capture.patch`,
upstream PR #15) rejects any capture that reaches an `rts` within eight
instructions, so `$DA6A` is classified as an ordinary call. The pops never unwind
the two C frames, the terminal re-enters its loop, and choosing Yes returns to
Hotel Options - exactly the reported symptom.

Two refinements were tried and both were reverted:

* dropping the `rts` rejection from `capture_is_takeover` alone: no effect, because
  the handler calls into `$C0DA` early, so the static proof never reaches the pop;
* distinguishing word pops (`$0E34`'s saved-register restores, the leak patch 0002
  fixed) from longword pops (real return captures) with a separate
  `_sp_popped_l` counter: the terminal now exits, but the game lands on a black
  screen, and a plain run then froze on the boot logo - a regression. Reverted to
  the shipped patch set.

Current build is the validated one: framebuffer `0x06B5...` / `0x11C1...` /
`0x876D...` at frames 3000/6000/12000, no watchdog, FM peak 7395, PSG peak 8182.
The check-out defect remains open with the cause identified above.

A third attempt derived the consumed slots from the emulated A7 itself
(`(g_cpu.A[7] - _esp_at_entry) / 4` at the rts, no opcode heuristics). It also
regressed boot: the run froze at the logo (`0x635CB0B6`) because enough ordinary
functions leave A7 above their entry value that spurious unwinds fire.

Conclusion: the capture cannot be classified by opcode shape, pop width or a
static proof - the three heuristics tried all fail in one direction or the other.
The correct place is the indirect call site (`$C436`'s `jsr (a0)`), which knows
the pushed slot address and can compare A7 after the call to decide how many
frames to unwind. That is the next thing to implement; the build below is the
validated one, with check-out still broken.

Tooling built for this investigation and kept: `--pad <hex>`,
`cosim_set_pad_override` in `cosim.c` (deterministic input for both backends),
`scripts/route-user*.input`, and the reverse-debug build wiring
(`GRG_REVERSE_DEBUG=ON` now defines `GEN_REVERSE_DEBUG`/`SONIC_REVERSE_DEBUG` and
the compat header includes `reverse_debug.h`).

### Check-out fixed (call-site slot accounting)

The fix is `patches/0003-call-site-return-slots.patch`: an indirect `jsr`/`bsr`
site compares A7 against its own pushed slot after the call. If the callee consumed
more than its own return (`_tail_k >= 2`), the final `rts` slot is restored and that
many C frames are unwound - what the guest does at `$DA6A`.

Verified: `scripts/route-user.input` now ends in the hotel room (identical frame to
the interpreter), boot hashes unchanged, 12 000 frames without a watchdog, FM 7395,
PSG 8182, PSG was 0 before the audio work.

Open: after firing in the room, ammo depletes but the shot animation does not play
and the muzzle-flash sprite stays on screen; a second trigger pull has no effect
(`scripts/route-fire.input` reproduces it - frames f1..f3 are byte-identical).

### Shooting: recompiled code matches the interpreter

Driving both backends through check-out and then a trigger pull with injected pad
input (`pad <hex>`, same checkpoint both sides): the first differing checkpoint is
one frame after the shot, and two frames later **all 64 KB of work RAM are
identical** (checked region by region). Registers (A7, D0, D1, SR) are identical
too. So the shot itself is reproduced faithfully; the "stuck muzzle sprite / no
animation" is not a recompiled-vs-interpreter divergence.

Comparing screenshots from scripted runs of the two backends is not a valid check
here: the interpreter executes at a different rate, so the same script directive
lands on a different game frame and every pair differs (27-43 mean abs diff) even
in the room before firing.

Next reference needed: an external emulator capture of the same action. The open
question is whether the sprite that persists is the aiming reticle (which stays
until the cursor moves) rather than a muzzle flash - that would make it game
behaviour, not a port defect.

### 2026-11-15: automated intro harness - and a correction

Built `scripts/autotest-intro.ps1`: it launches the port N times, randomises the
frame on which START/A are pressed (human-like timing), records a framebuffer hash
per frame, and reports a "scene timeline" (runs of an identical frame hash). A
skipped cutscene shows up as a missing/short segment. `-Analyze <err>` re-parses a
finished run without launching anything, and uncapped runs make a 7000-frame pass
take ~30 s instead of 150 s.

Result over two 8-launch batches (seeds 7 and 11): **every completed launch was
identical - 28 scenes, longest scene 1604-1640 frames**, with the timeline simply
shifted by the randomised press frames. No skip was reproduced.

Correction worth recording: an intermediate batch reported 9 and 16 scenes for two
launches, which looked like a reproduction. It was not - those runs were truncated
because a clean-up step in another command killed the game mid-run. The same
randomised timings (w=2135/1401/1630) produce 28 scenes when the run is left alone.
Lesson: never clean up game processes while a measurement batch is running.

So the skip remains a live-session phenomenon that automated, scripted launches do
not reproduce; the harness is ready for the moment a session can be recorded with
`scripts/record-session.ps1` (per-frame timeline + RAM ring + input replay).

### Session recording with automatic scene labelling (2026-11-15)

`scripts/record-session.ps1` launches the port and records, under
`build/sessions/<timestamp>/`: a per-frame `timeline.err`, a RAM ring, a clean
`run.log`, and a `summary.txt` produced by `tools/label_session.py`.

The labeller turns consecutive identical frame hashes into named "scenes" and can
compare a session against a catalog built from a known-good run:

```
python tools/label_session.py <session>.err --build  build/scene-catalog.json
python tools/label_session.py <session>.err --compare build/scene-catalog.json
```

The comparison uses an ordered alignment (difflib), not hash lookup, because the
logo hash repeats - a hash-keyed comparison produced bogus "truncated scene"
reports. It also distinguishes a **short log** (session ended early) from a
**skipped scene**, which was exactly the trap that produced a false reproduction
earlier: four phantom "skips" were really truncated logs.

Known-good reference: every complete automated launch shows 28 scenes with the
longest near 1600 frames; a catalog built from one is enough to flag a missing
cutscene in a future session.

The catalog itself is not committed (it is derived from game imagery); rebuild it
from any clean session.

### 2026-11-15 (later): the skip detector works, but the scripted baseline is unreliable

`tools/label_session.py` now correctly flags a shortened scene. On a session the
user reports as broken it said:

```
TRUNCATED scenes (1):
  scene 07 expected 1364 frames, got 248
```

That fix also exposed a flaw in the *baseline*: the catalog's 1364-frame scene came
from a scripted run, and scripted runs are not comparable. `input_script` advances
one directive per **wall** frame while the game advances on its own clock, so on a
slow host the script races ahead and its START press lands during the intro -
skipping the very scene being measured. Evidence: scripted runs currently finish at
~1900 game frames instead of the 9000 they asked for, and their skyline scene is
63-163 frames regardless of whether RAM dumping is enabled.

So the scripted "skip" is a harness artefact, not the game. Only a live session
recorded through `scripts/record-session.ps1` is trustworthy for this comparison,
and its catalog must be built from another live session, not from a scripted one.

### 2026-11-15 (evening): the emulation is deterministic under pacing

Two paced runs (hidden window, dummy audio, 3000 frames, same input) produced
**identical** guest and audio state:

```
state_fnv1a64      8AB8A4BDEAB93FF0   8AB8A4BDEAB93FF0
audio_state_fnv1a64 12DE410E3AB2812F  12DE410E3AB2812F
```

Only host-side counters differed (cycles measured per frame, audio overflow drops
39034 vs 65201). So the port does not randomly corrupt its own state: given the
same input, it is bit-identical run to run.

Consequences for the intermittent sound/skip report:

* The skip cannot come from non-deterministic emulation; it must come from a
  different *input trajectory* (the player pressing at different moments), or from
  the live presentation/audio path in a way that does not touch guest state.
* Automated input is limited to `--input-script`; synthetic keys (`keybd_event`)
  never reach the runner - proven with `DSH_PAD_LOG`, which recorded zero pad
  transitions while the driver pressed START/A. Keyboard automation is therefore
  not available in this environment.
* Every scripted variation tried (fixed timing, randomised timing, A-mashing,
  parallel instances, hidden windows) gives the same clean intro: skyline 1329
  frames, ambush 1602, 9000 frames.

Open next step: reproduce the *interactive* input trajectory on a reference
emulator and compare (BizHawk showed the same ROM booting but the scripted route
did not complete in this environment).

### 2026-11-15: music death isolated to Z80 timing after an intro skip

Recorded a live session where the player pressed exactly Enter, Z, Z (verified in
the replay: 0x80 at frame 1342, 0x40 at 1473, 0x40 at 1546). The second A lands as
the intro starts, which is the game's cutscene skip: the skyline scene ran 60
frames instead of 1364. Device-side stats from that session: flushes=2733
dropped=0 underruns=0, so the audio device never starved.

Replaying the same input route on both backends:

```
recompiled   fm first3rd=6570  mid3rd=3977  last3rd= 383   (music dies)
interpreter  fm first3rd=7529  mid3rd=3819  last3rd=2396   (music continues)
```

Co-simulation on the same route: the 68K state hashes agree, but from frame 1565
onward `z80`, `z80ram` and `fm` differ for every checkpoint (60/60 checks). At that
frame `master_cycle` is identical (1403198640) while `z80_debt` is 15 in the
recompiled build and 0 in the interpreter - the sound CPU is clocked 15 master
cycles behind and never catches up.

Earlier divergence exists but is not yet attributable: the first frame where the
Z80 subsystem hash differs is 25 (boot), and `cum` first differs at frame 66 by 58
cycles / 3 instructions. Those early differences were previously observed to
reconverge; the one that persists starts with the cutscene skip.

Next concrete step: use the co-sim INSN clock drill to compare per-instruction
cycles inside frames 1546-1565 and name the instruction whose cost differs.

### 2026-11-15: instruction trace localizes the split to a return-capture site

Added a per-instruction trace (GEN_TRACE) and a ring buffer dumped on a shared
event, so both backends' dumps end at the same instruction. Framing the two dumps
from the tail gives a 42212-instruction common suffix and places the first split at
ROM `$000EB2-$000EBE`, which disassembles as:

```
000EBC  move.l (a7)+, d1
000EBE  rts
```

That is exactly the return-capture machinery added by patches 0002/0003, and the
generated code there reads

```c
/* $000EBE */
if (g_split_sp_popped >= 4) { g_rte_pending = g_split_sp_popped / 4; g_split_sp_popped = 0; }
```

So the leading hypothesis is that the return-slot consumption itself perturbs the
68K timing in that helper (the co-sim build disables register spans, so spans are
not the cause of this particular split).

Controlled test for next session: build the co-sim with patch 0002's `rts` gating
removed and re-run the trace. If the frame-66 instruction-count difference (8505 vs
8502) disappears, the patch is the cause and needs a timing-neutral form; if it
persists, the split is elsewhere and the trace data is already in place to find it.

### 2026-11-15: Z80 RAM diff at the first divergent frame

Added a `z80mem <addr> <len>` command to the co-sim and compared Z80 RAM at frame
25, the first frame whose `z80` hash differs. Chunks 24-27 ($1800-$1BFF), the SMPS
driver's data area, differ. Byte-level diff of $1800-$1BFF:

```
$18FB  recomp=00  interp=FF        (same pattern every $27 bytes through $1ACF)
$1B1A  recomp=00  interp=18        ; 18 26 42 C9 06 09 - driver bytes
$1B1F  recomp=00  interp=09
```

So at frame 25 the recompiled backend's Z80 RAM is still zero in a region the
interpreter has already filled: the driver upload / init is running at a different
point relative to the frame boundary, not producing different values.

Caveat: earlier measurements showed z80ram differences that reconverge in bursts,
so this may be the same transient. The `z80mem` command now exists to check
convergence byte-for-byte instead of by hash.

### 2026-11-15: the two backends run a different number of Z80 line-steps

Added a per-line Z80 stepping log (`GENESIS_Z80_LOG`: line, master cycle, debt in/out,
PC in/out) and diffed it over 40 frames:

```
A (recompiled) 3083 step lines
B (interpreter) 3082 step lines
```

The logs agree exactly for the first 719 steps (line, master cycle, debt in/out and PC
all identical), then one backend performs an extra Z80 line step. A full line is 228
Z80 cycles, so from that point the sound CPU is a line out of phase - which is the
kind of offset that breaks a driver whose tempo/IRQ handling is line-timed, and
matches the earlier observation that z80ram differs from frame 25 and that
z80_debt ends up non-zero after an input burst.

So the defect is not in the Z80 core or the driver data, but in how many times the
machine steps the Z80 per frame - the count itself differs between the recompiled
68K backend and the interpreter.

### 2026-11-15 (late): the single differing byte is on the Z80 stack

Added a write watchpoint (`GENESIS_Z80_WATCH=<hex offset>`) covering both the Z80
and the 68K side of Z80 RAM. Watching `$1B14` over the skip route: both backends
write it 4854 times through an identical instruction sequence, and only the last
write differs:

```
A (recompiled)   pc=02BD  val=BB
B (interpreter)  pc=02BB  val=BD
```

`$1B14` is inside the Z80 stack, and the value is a pushed pointer/return address
whose low byte differs by 2 - the same 2-byte offset as the diverging PCs. So the
one differing byte is a *symptom*: the Z80 follows a slightly different control
path (a pushed address 02BB vs 02BD), not a corrupted driver variable.

Disassembly of the uploaded driver around there:

```
02A4  CD B7 02   CALL $02B7
02B7  C9         RET
02B8  26 36      LD H,$36
02BA  27         DAA
02BB  CB 46      BIT 0,(HL)
02BD  CA BB 02   JP Z,$02BB
```

Next: find which Z80 branch produces the 02BB/02BD difference - the stack word tells
us the two paths, and the driver disassembly above is the region to read.

### 2026-11-15 (final for the night): causal chain identified

`machine_z80_stamp()` returns `s_line_base + s_z80_off`, and the YM2612 status
read serves its timer flags with `ym_abs_z80_stamp()` built from that value:

```c
static uint64_t ym_abs_z80_stamp(void) {
    return (uint64_t)g_snd_frame * MASTER_CYCLES_PER_FRAME + (uint64_t)machine_z80_stamp();
}
static void ym_timer_update(GenesisBus *b, uint64_t now) {
    if (!b->ym_timer_b_running || b->ym_timer_b_period == 0 || now < b->ym_timer_b_deadline)
        return;
    b->ym_status |= 0x02u;      /* timer-B overflow flag */
    ...
}
```

`s_z80_off` is set per Z80 instruction as `done * MASTER_PER_Z80`, so it carries the
Z80's overshoot within the line. After the cutscene skip the two backends reach the
same driver instruction with slightly different `done` (the earlier measurement:
instruction counts 3083 vs 3082 over 40 frames), which shifts `now` by a few master
cycles. When a read lands within that window of a timer deadline, `now < deadline`
flips, the overflow flag flips, and the driver takes the other branch - which is
exactly the 02BB/02BD difference seen on the Z80 stack, followed by the music
stopping.

So the chain is:

1. 68K chunk / Z80 step interleaving differs by a few cycles between backends
2. `s_z80_off` (and the carried debt) differs at the same driver instruction
3. the YM timer-B deadline comparison flips
4. the SMPS driver branches differently (02BB vs 02BD)
5. FM music stops; the device still receives samples (0 underruns)

Fix direction: make the stamp used for timer comparisons the exact master cycle of
the access rather than a line-relative value carrying instruction overshoot (or give
the deadline comparison a small guard band so a few-cycle difference cannot flip it).

### 2026-11-15 (fix): YM timer guard, and what "383" actually means

Patch `0006-ym-timer-guard.patch` requires the YM timer-B deadline comparison to be
64 master cycles past the deadline before flagging overflow. Result on the cutscene
skip route (identical inputs both sides):

```
recompiled before fix : fm last3rd  383  (dead)
recompiled with fix   : fm last3rd 4822  (alive)
interpreter           : fm last3rd 2396  (alive)
```

Validated boot hashes unchanged (frames 1000/2000/3000/6000 = 45E5/E29B/06B5/11C1)
and two paced runs remain bit-identical (state 366C4771EC6782A2).

Correction worth keeping: `383` is **not** by itself a failure signature. On the full
9000-frame route both backends end their last third at 383 because that part of the
route is a quiet scene (interpreter: 383; recompiled: 383). The discriminator is only
meaningful on a route where the interpreter keeps playing (the skip route), which is
why earlier comparisons that used the full route were ambiguous.
