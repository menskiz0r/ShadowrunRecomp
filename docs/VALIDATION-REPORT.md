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

### 2026-11-15 (correction): the timer guard did not fix live play

The 64-cycle timer guard was validated on a scripted skip route (presses at frames
1342/1473/1546) where it moved FM last-third from 383 to 4822. A live session from
the player pressed at 1253/1370/1401 - a different route - and with the guard the
session still ended at **383**. The guard moved the decision threshold rather than
removing the sensitivity, so it has been reverted and patch 0006 deleted.

Lesson: a fix must be validated on more than one input trajectory, and the
recording of the failing live session is the case that matters.

Also: replaying an archived session currently fails with `invalid startup SRAM
attachment` when the replay's `.sav` sidecar is the one the recorder copies after
the session; the framework's `tools/replay_diagnostic.py` on an untouched
`build/logs/Shadowrun-feedback.replay` works, so the archived sidecar handling needs
looking at before replays can be used for verification.

### 2026-11-15 (late): a live session now replays exactly

After fixing the recorder's startup-SRAM archiving, a live 5042-frame session
replayed with `all 5042 recorded executions matched`. That session is the one where
the player reported "shooting sprites do not disappear, then shooting breaks, then
the game hangs":

- FM audio: first third 6570, mid third 383, last third 383 -> the music still dies
  during the session
- 139 scenes, two truncated (the cutscene skip plus one more)
- the emulator kept running to frame 5042 with changing images; no watchdog or crash
  report was produced, so the "hang" is the game itself stalling rather than the
  runner

This gives two deterministic regression cases:
1. the sound loss (`sessions/20261115-204746/replay`)
2. the combat stall, same replay

Both can be replayed headlessly with `scripts/replay-run.ps1`, which is how any fix
should be validated from now on - not against a scripted route.

### 2026-11-16: combat stall confirmed as interior-label dispatch, from the player's own session

Replaying the live combat session (5042 frames, all inputs matched) produced the
recompiler's miss reports. `interior_label_misses.toml`:

```
[interior_labels]
addresses = [
  0x00B3EE, # session 1 frame 2656
  0x014E0A, # session 1 frame 2656
  0x00AC4E, # session 1 frame 2656
  0x00B49C, # session 1 frame 3248
]
```

`dispatch_misses.toml` is empty, so the gap is specifically *interior* dispatch: the
game computes a jump into the middle of an existing function and no entry point
exists. The frames (2656, 3248) are the combat moments in that session.

Fix: in-function entry points. For each listed address the generator should emit
`func_XXXX_from(n)` with a switch that jumps to the matching label (the generated
code already uses labels for branches), plus a thunk registered in the dispatch
table, leaving the plain `func_XXXX()` wrapper untouched. Seeding them as functions
is not an option (it splits the parent and previously broke audio + crashed).

### 2026-11-16: interior entries - what the generator already has and what is missing

Findings from reading the generator:

- multi-entry functions already exist: when a function is an alias host the codegen
  emits `void func_XXXX(uint32_t _entry)` with `switch (_entry) { case 0xADDR: goto
  label_ADDR; ... }`, so the runtime shape for the fix is already there
- `[functions] function_aliases = true` only applies *branch-proven* aliases
  ("Entry ownership audit: 26 branch-proven alias candidates"), and enabling it did
  **not** produce labels for 0x00B3EE/0x014E0A/0x00AC4E/0x00B49C, because those are
  reached by computed jumps, not branches
- the only address configs are `[functions].extra` / `extra_seeds` (seeding splits
  parents - previously broke audio and crashed)

So the work is:

1. add `[functions] interior_entries = [0x00B3EE, 0x014E0A, 0x00AC4E, 0x00B49C]`
   to `GameConfig` (recompiler/src/game_config.c, alongside `extra_funcs`)
2. in code_generator.c force `label_<addr>:;` for listed addresses even when they
   are not branch targets, and force the alias-host form for their owner functions
3. emit a thunk per interior address and register it in the dispatch table
4. regenerate and replay session 20261115-204746: `interior_label_misses.toml`
   should be empty and frames 2656/3248 should pass without stalling

### 2026-11-16: combat stall fixed - the miss addresses needed real function entries

The four reported interior addresses were not actually interior: `$00B3EE` sits
directly after an `RTS` (`4E 75` at `$00B3EC`), so the block is reachable only
through the code pointer the game stores. Adding them as `[functions].late_extra`
function entries (rather than as aliases inside a parent) is therefore correct and
does not split any scanned function.

Iterating with the player's replay as the oracle:

1. `late_extra = [0x00B3EE, 0x014E0A, 0x00AC4E, 0x00B49C]`
   -> replay matches all 5042 inputs; scenes drop from 139 to 35; the miss report
   now lists two more addresses (`0x00B07E`, `0x00B38A`)
2. adding those two
   -> `interior_label_misses.toml` comes back **empty**

Verified after the fix:
- all 5042 replay inputs matched
- boot hashes unchanged (1000/2000/3000/6000 = 45E5/E29B/06B5/11C1)
- two runs bit-identical (state 66975B9FE678D9A8, audio 7793612B06795D0B)

Also added two diagnostic switches: `GENESIS_REPLAY_ALLOW_OTHER_BUILD` and
`GENESIS_REPLAY_IGNORE_CHECKPOINTS`, so an old recording can be replayed against a
new build - which is what makes this iteration loop possible.

### 2026-11-16: headless oracle for the sound loss

`scripts/replay-run.ps1` now also captures the pre-DRC audio stream, so the sound
defect can be measured without a live session. Replaying the recorded combat session
(`sessions/20261115-204746/replay`, 5042 inputs) reproduces it exactly:

```
recompiled   fm peak=6570  first=6570  mid=383  last=383     <- music dies mid-session
interpreter  fm peak=7529  first=7529  mid=4382 last=380     <- music survives
```

Both runs use `GENESIS_REPLAY_ALLOW_OTHER_BUILD=1` and
`GENESIS_REPLAY_IGNORE_CHECKPOINTS=1` so an older recording can be replayed against a
new build.

A per-line Z80 log diff over the same replay is not yet usable: the replayed build
fast-forwards stretches where no input changes (master_cycle jumps ~6 s at step 720)
while the interpreter steps every line, so the two logs must be aligned by frame
number. The log currently records only the scanline, not the frame.

### 2026-11-16: the interpreter now shares the recompiled timing model

The shipping interpreter used PRM cycle estimates while the co-sim used the
recompiler's measured cost table, so any recompiled-vs-interpreter audio comparison
was comparing two timing models. Fixed: the main target now also links
`generation-stage/<prefix>/<prefix>_cycles.c` and `runner/game_cycles.c`, and
`interp_account_cycles` charges `game_insn_cost()` unconditionally (PRM only as a
fallback for RAM-resident code).

With one timing model the comparison is fair and the result is unchanged:

```
recompiled            fm thirds 6570 / 383 / 4382? -> 6570 / 383 / 383   (music dies)
interpreter (shared)  fm thirds 7437 / 4226 / 380                        (music survives)
```

Gameplay hashes are unaffected (1000/2000/3000/4000 = 45E5/E29B/06B5/29F9).

Frame-aligned per-line Z80 logs over the same replay now diverge at **frame 25,
line 86** (`pc 2274 vs 2275`, debt 3 vs 2) and 98% of subsequent lines differ. That
places the sound defect in Z80 stepping from boot (most likely when and how the Z80
is released from reset relative to the 68K chunk), not in the YM timer comparison -
the timer flag flip seen earlier is a downstream symptom.

### 2026-11-16: the Z80 is released from reset on a different line in each backend

With the shared timing model, instrumenting the reset-release point shows:

```
recompiled   [Z80REL] frame=25 line=86 master=22695120 debt=2
interpreter  [Z80REL] frame=25 line=82 master=22681440 debt=2
```

Same frame, four scanlines apart. The Z80 is stepped once per scanline
(`step_z80(m, Z80_PER_LINE)`), so a bus-request/reset written mid-line only takes
effect at the next line boundary. Which line that is depends on where the 68K chunk
ends, and the recompiled blocks and the interpreter yield at different granularity -
so the Z80 starts running at a different master cycle and its accounting never
re-aligns (98% of later lines differ).

An attempted fix that advanced the Z80 to the 68K's intra-line position before the
buswrite had no effect (release stayed at line 86 vs 82, FM unchanged at 383),
confirming that the line assignment is decided by the 68K chunk, not the Z80 advance.

Real fix (architectural): interleave Z80 stepping with 68K execution at finer
granularity than one scanline - e.g. advance the Z80 by the same cycles the 68K just
ran, so a mid-line buswrite is seen at the exact master cycle in both backends.

### 2026-11-16: syncing the Z80 on bus writes is not sufficient

Calling an intra-line Z80 sync immediately after a bus-request/reset write changed the
audio (FM peak 6570 -> 6954, first third different) but the music still died
(mid third 383, interpreter 4226). Reverted.

Conclusion: the Z80's cycle position matters for every access, not just the bus
control writes, so the fix has to be continuous interleaving - advance the Z80 by the
cycles the 68K just ran as it runs them - rather than a hook at one register.

### 2026-11-16: cheaper hypotheses tested and disproven

Instrumented `glue_run_game_chunk` to log why each chunk returns (frame, scanline,
yield reason, leftover budget) and compared both backends over the first 60 frames.

At frame 32, line 102 the recompiled build returns with `budget=332` and reports
`vblank-park` from line 103 onward, while the interpreter keeps yielding with the
budget exhausted and keeps executing. Initially this looked like a cycle undercount,
but it is the expected difference: the recompiled code parks at its WaitForVBlank
fast path, while the forced interpreter runs the wait loop as ordinary instructions.
Not the bug.

Register-span batching was the next suspect, so a runtime switch was added
(`GENESIS_NO_SPANS=1` disables `GEN_NATIVE_REGISTER_SPAN_READY`) and the replay was
re-run with spans off:

```
spans on : fm 6570/383/383
spans off: fm 6570/383/383     (interpreter 7437/4226/380)
```

Identical, so span batching is not the cause either. Also reverted a build change that
linked the cycle table into the shipping target: the generator only emits
`generation-stage/<prefix>/<prefix>_cycles.c` for the co-sim configuration, so the
main target could not compile against it.

Remaining candidate is unchanged: the Z80 is stepped once per scanline, so the phase
relationship between Z80 execution and 68K writes depends on where the 68K chunk ends.
The fix is continuous interleaving (advance the Z80 by the cycles the 68K just ran).

### 2026-11-16: slice interleaving tested - not the fix either

Rebuilt the frame loop to interleave the Z80 with the 68K at slice granularity
(`GENISIS_Z80_SLICES` slices per scanline, each `glue_run_game_chunk(M68K_PER_LINE/n)`
followed by a cumulative `step_z80`), and measured the replay oracle:

```
 8 slices: fm peak 7687  first 7687  mid 383  last 383
32 slices: fm peak 7864  first 7864  mid 380  last 380
128 slices: fm peak 7343 first 7343  mid 380  last 380
```

Finer interleaving does not restore the music and at 32+ slices it dies earlier.
Reverted to the original once-per-scanline stepping (boot hash 45E5 confirmed).

So the Z80/68K interleaving granularity is not the mechanism either. The remaining
line of attack is the command stream itself: log every 68K write into Z80 RAM during
the replay on both backends and compare - if the recompiled 68K sends a different
sequence (a stop command, or stops sending the per-frame tick) that is the defect,
and it would be visible as a difference in that stream rather than in timing.

### 2026-11-16: the music stops because the 68K stops commanding the driver

Added `GENESIS_Z80CMD_LOG`, which logs every 68K write into Z80 RAM (the sound
driver's command mailbox), and compared both backends over the whole replay:

```
commands: recompiled 42248   interpreter 42335
last recompiled command: frame 3389   off=0036 val=22
last interpreter command: frame 4995
```

Both backends send an identical command sequence (the first 41964 commands match,
modulo frame numbering), both pause at frame 3389 - a scene change where the game
re-uploads part of the driver (writes at Z80 $1B5C-$1B61 with values FF,10,..,3C and
a trigger byte at $0036) - and then:

- the interpreter resumes commanding the driver from ~frame 3500 to 4995
- the recompiled build never sends another command

The audio evidence matches: the FM stream never goes fully silent, it drops to
residual SFX (~383) from that point, because nothing drives the music any more.

So the defect is NOT the Z80 timer or the interleaving: it is the sound-driver
re-initialisation at a scene change, after which the game's 68K side gives up on the
driver. The likely shape is the upload/handshake loop timing out because the Z80
state it waits on is never set.

A `[Z80RD]` read probe was added to see what the 68K polls while stuck, but it did not
fire - the 68K's Z80 reads go through a path not yet hooked.

### 2026-11-16: after the pause the 68K never touches the driver again

Hooked the real 68K Z80 read path (`gbus_read16`, the byte-readable Z80 RAM window)
and replayed with the command log enabled. After frame 3389 the 68K performs only
**two** Z80 reads, both of the trigger byte `$A00036` - so it is not spinning on a
handshake. The game simply stops calling its sound code.

That rules out "the handshake times out": the 68K never asks again.

Work-RAM comparison at frame 3390 shows 197 differing bytes concentrated in
`$FF0000-$FF00FF`, a table of small values (1..6) that looks like object/animation
state rather than a music flag. The command streams first differ in value at frame
1626, so the game state begins to split there (after the intro skip) and the sound
subsystem is abandoned 1700 frames later.

Next: trace 68K execution around frame 1626 (the existing GEN_TRACE hook records the
address of most instructions) to see which routine takes a different path, then work
forward to the point where the per-frame sound tick stops being called.

### 2026-11-16: full-address tracing, and why the comparison still isn't exact

The generator now emits an address for every GEN_TRACE site (32983 sites with a real
address, none zero), via a file-scope `s_emit_pc` fallback set by the emission loop
(the per-instruction emitter itself has no `pc` parameter). Boot hashes are unchanged
(45E5/E29B/06B5).

Re-running the frame-1627 comparison still shows the recompiled side repeating a
single address with varying costs (`pc=00160E` with 4, 8, 10, 14, 16), so `s_emit_pc`
is stale for those instructions - the per-instruction emitter must take the address as
a parameter rather than reading a global that some other emitter path overwrites.

State of the sound investigation, unchanged in substance:
- music stops because the game stops commanding the driver (command stream proof)
- game state splits around frame 1626, shortly after the intro skip
- the recompiled 68K never retries the driver (2 Z80 reads total after the pause)
- all timing hypotheses (timer guard, span batching, bus sync, 8/32/128-slice
  interleaving) tested and disproven

### 2026-11-16: trace instrumentation status (stale-address caveat)

The generator now passes the emission loop's `pc` into emit_instr (new trailing
`ins_addr` parameter) and uses it for the per-instruction trace, so the ordinary
instruction path logs real addresses (verified: `GEN_TRACE(0x000D92u, 10)` next to its
`/* $000D92 */` comment). Boot hashes unchanged.

However the frame-1627 recompiled trace still contains 203157 of 262144 entries at a
single address `$00160E`, and `$00160E` does not appear anywhere in the generated code
- so those entries come from an emission path that does not set the address and falls
back to the stale `s_emit_pc` global (the step-runtime / split emitters that receive
`ins->addr`, which is often 0). Until every emitter passes a real address the
recompiled trace cannot be compared instruction-for-instruction.

What the traces do show today:
- interpreter at frame 1627: parked in the VBlank wait ($000BDE/$000BE4), working at $001A0C
- recompiled at frame 1627: dominated by the un-attributed path above; 106 distinct
  addresses versus the interpreter's 88

So the comparison is close but not yet trustworthy. Next step: give the step-runtime
and split-tail emitters the real instruction address (they currently pass ins->addr),
then re-run the frame-1627 comparison.

### 2026-11-16: trace fully attributed - the recompiled build loops in a VDP transfer

The last 24508 zero-address trace sites were the loop's *second* cycle-accounting call
(`emit_cycle_accounting(f_func, "  ", cyc, 0)` after emit_instr, for VBlank checks).
Passing `pc` there makes the generated trace 32982/32983 attributed.

Frame-1627 comparison, both traces fully attributed:

```
recompiled : 262144 entries, top $0015D4/$0015D8/$0015DA/$0015DE (12313 each)
interpreter: 262144 entries, top $000BDE/$000BE4 (129588 each = the VBlank wait)
```

The recompiled 68K spends the frame in this loop:

```
0015D4  move.b (a1,d4.w), d7
0015D8  addq.w #1, d4
0015DA  andi.w #$7ff, d4        ; 2 KB ring wrap
0015DE  move.b d7, (a1,d6.w)
0015E2  addq.w #1, d6
0015E4  andi.w #$7ff, d6
0015E8  btst.b #0, d2
0015EE  move.w d7, $c00000.l    ; VDP data port
0015FA  dbra d3, $0015D4
```

i.e. a buffer-copy + VDP-data transfer loop, while the interpreter is parked at its
VBlank wait. A transfer that keeps re-running every frame would starve the rest of the
game - including the per-frame sound tick - which matches the command-stream finding
(the 68K stops commanding the driver).

Next: find what re-arms this loop every frame (a transfer-request flag that never
clears, or a VDP status bit the game polls).

### 2026-11-16: the handshake byte differs, and that is why the game gives up

Found the sound handshake routine by searching the ROM for the mailbox address it
uses ($A00036): one reference, `$052E5C lea.l $a00036.l,a0`, inside the routine at
$052E4E that pops its return address into a0, takes BUSREQ, polls the ack, and reads
one response byte.

Comparing mailbox reads on the replay:

```
interpreter: f=3382 val=3F   f=3389 val=02   then f=4407 val=05, 4408 08, 4465 0B, ...
recompiled : f=3382 val=1C   f=3389 val=1F   then nothing at all
```

So at the scene-change handshake the recompiled build reads a different driver response
(1C/1F vs 3F/02) and afterwards never calls the read routine again - the game concludes
the driver is not responding and stops commanding it, which is exactly the command-stream
stop measured earlier.

This connects every previous observation: driver state diverges during the earlier scene
transition -> the handshake byte is wrong at the re-init -> the game abandons the sound
driver -> no more music commands -> music dies while SFX continue.

Remaining question: why the driver's response byte differs at that moment (the Z80 RAM
state it reads from), which is the same state divergence tracked from frame 25.

### 2026-11-16: the mailbox protocol - deposit, echo, give up

Watched Z80 RAM offset $0036 (the handshake byte) on both backends. The 68K deposits
an incrementing sequence there:

```
recompiled : ... 18,19,1B,1C (f=3279)  1E,1F (f=3382)  21,22 (f=3389)  then nothing
interpreter: ... continues through 06..16 up to f=4995
```

and the read-back differs from what was deposited (recompiled deposits 1E,1F at f=3382
and reads 1C; the interpreter reads 3F at f=3389). After those mismatches the
recompiled build never deposits another command.

So the protocol is deposit -> read-back (the driver's echo/status) -> decide, and the
recompiled build's read-back does not match, so the game stops commanding the driver.

The read-back is produced by the Z80 driver from its own state, which diverged earlier;
the remaining question is which driver state decides the echo. With `GENESIS_Z80_WATCH`
and `z80mem` now available, the next step is to watch the driver's write to $0036
(Z80 side) around frames 3380-3390 in both backends and compare the values.

### 2026-11-17: the sound protocol mapped; the stop is game-side, not a blocked sender

Static analysis of the sound library plus targeted watches resolved the protocol:

- `$052E4E` takes BUSREQ, polls the ack and reads `$A00036`; `$052EB0`/`$052EC6` push
  bytes through `$052EA2`, which writes into a 64-byte ring at `$A01B40` with an `$FF`
  sentinel; the ring write index lives at `$A00036` (so the differing values seen at
  frames 3382/3389 are just differing command counts, not a failed echo).
- Bus wrappers: `$052DC2` (take: write `$100` to `$A11100`, poll bit 0), `$052DD6`
  (release: write `$0`).
- Music tick: `$0530DE` gates on two RAM flags `$FFFC0A` / `$FFFC08` and then sends
  through `$052F3C`. It has 77 call sites.

Measurements on the replay:

- both flags read `0001` in both backends at frames 3000/3300/3390/3600/4800, so the
  tick is enabled in both
- the Z80 driver is alive at frame 3389 (260 line-steps, pc $0699/$0701) and never
  writes the ring (only 64 boot zero-fills in both)
- ring writes: 1058 (recompiled) vs 1110 (interpreter) - comparable totals, but the
  recompiled build's last write is frame 3389 while the interpreter continues to 4995
- traces at frames 4000/4466 show both backends executing the same hot code
  (`$01DF44`, `$01DFBA`, `$00EBB6`); the sender entry points are not in those windows

Conclusion: the game is not blocked from sending commands - the gate flags are open and
the driver is alive. The recompiled build simply stops needing to send, which matches
the earlier observation that its game state runs ahead/gets stuck (frame 1627 showed it
inside a VRAM decompressor while the interpreter idled at VBlank). So the remaining
defect is in game-flow, not in the sound handshake.

### 2026-11-17: frame-numbered comparisons are not valid (phase offset)

Using the 169 RAM snapshots from both backends (every 30 frames) and computing, per
address, the first frame at which it differs:

```
frame   30 : 1 address    ($FFFFF3, stack)
frame   60 : 8 addresses  ($FFF9EF, $FFF9F7 are inside the game's VBlank counter)
frame   90 : 812 addresses at once
```

The earliest differences are the VBlank counter phase and stack, and the 812-address
burst at frame 90 is one frame of offset propagating. So the two backends reach frame N
at different guest moments - the recompiled code parks at its VBlank fast path while the
forced interpreter runs the wait loop as instructions, which shifts their position
within the frame.

Consequence: comparing work RAM, traces or audio segments by frame NUMBER is invalid;
only cycle-aligned comparison (the co-sim) is. Several earlier conclusions drawn from
frame-indexed RAM diffs should be treated as suspect for this reason, including the
"197 differing bytes" observation at frame 3390.

This also means the remaining question ("why does the recompiled 68K stop sending sound
commands after frame 3389") cannot be answered by frame-indexed comparison: it needs a
common anchor (a specific sound command, a VBlank count, or the co-sim).

### 2026-11-17: valid comparison method found; one persistent game-time difference

Frame-indexed comparison is invalid (phase offset), so both replays were re-run with
`--autodump-ram-every 1` and the snapshots were matched by the game's own VBlank
counter (`$FFF9EC`) instead of wall frames: 4866 game frames align out of 4887.

Results:
- boot divergence is transient (167 bytes at game-frame 37, back to 5 by frame 53)
- a large transient at game-frame 1806 (33769 bytes) is a scene load
- during the "silence window" (game frames 3200-4900) states differ by only ~200-500
  bytes, i.e. the runs track each other closely
- the music difference is real in game time: the recompiled build's last driver command
  is at game-frame **3235**, the interpreter's at **4867**, and the recompiled build
  reaches game-frame 4867 at wall frame 5021 without sending anything

One persistent, game-time-aligned difference stands out:

```
vblank   $FF019F rec/int
  3200    03 / 02
  3368+   00 / 05   (persists to the end)
```

So `$FF019F` is 00 in the recompiled build where the interpreter holds 05. It is not
addressed by any absolute-long reference in the ROM (accessed through a base register),
so the next step is to find its writer with a RAM write watchpoint and see whether it
is a music/track selection byte.

### 2026-11-17: the track selection is RNG-driven, and the RNG seed differs

Chased the persistent `$FF019F` difference to its writer and then to the state byte it
copies:

```
0556B0  move.b $FFF0DD.l, (a4)     ; copy state byte into a table
```

`$FFF0DD` is produced by a 7-try weighted selector at `$0DBA`:

```
000DC6  clr.b  $FFF0DD.l
000DD0  jsr    $0D3A               ; RNG
000DEC  addq.b #1,$FFF0DD.l        ; count the hits
000DF2  dbra   d6,$0DCE
```

and `$0D3A` calls `$0D44`, a linear congruential generator with state `$FFF9F8`:

```
000D46  move.w $FFF9F8.l,d0
000D4C  mulu.w #$20E5,d0
000D50  addq.w #1,d0
000D52  move.w d0,$FFF9F8.l
```

The seed is produced at boot by `$0C2C` from a checksum of work RAM:

```
000C2C  cmpi.l #$12345678,$FFF9E8
000C3C  move.w #$3FDF,d7
000C46  add.l  (a0),d1             ; checksum every longword
000C48  move.l d0,(a0)+            ; and clear it
000C4E  move.w d1,$FFF9F8          ; seed
```

Measured: the two backends' seed values first differ at game frame 72 (`$FFFF`
recompiled vs `$5300` interpreter), so their RNG streams diverge from the first draw
and every downstream random choice (which track is requested, hence `$FFF0DD` /
`$FF019F` and the earlier command-stream stop) follows from it.

So the music difference is a downstream symptom of differing work RAM contents at the
moment of the boot checksum. Next step: compare RAM in the first 72 game frames and
identify the bytes that differ before the checksum runs (`$FFFFF3` at game frame 30 is
the first known one).

### 2026-11-17: RNG seed experiment isolates the remaining defect to the Z80 driver

Added `GENESIS_FORCE_SEED`, which overrides the boot writes of the RNG seed
(`$FFF9F8`) during the first 20 frames, so both backends can start from an identical
random stream (verified applied in both: the frame-14 seed write reads `5300`).

Results with the same seed (`5300`):

```
recompiled: commands=42248 last_command_frame=3389 fm thirds 6570/6570/383/383
interpreter: commands=42200 last_command_frame=3389 fm thirds 7529/7529/4445/380
```

Two conclusions:

1. The interpreter's own command stream changed when the seed was forced (its last
   command moved from frame 4995 to 3389), so the music *events* are RNG-driven - the
   seed really does control when tracks are requested.
2. Even with identical seeds the recompiled build's FM output goes quiet (383) while
   the interpreter keeps playing (4445). So the remaining defect is not in the 68K music
   logic; it is in what the Z80 driver does with the same commands.

Per-frame Z80 RAM dumps, aligned by the game VBlank counter, show where that starts:

```
game frame 0 : identical
game frame 2 : 27 bytes differ, first at $0036 (ring index 0x10 vs 0x00)
game frame 3 : 9 bytes differ ($003E, $0454, $1B1A-$1B1D, ...)
game frame 4-6: 1 byte ($1B1E: 06 vs 29)
game frame 3100+: a stable 849-byte difference
```

So the drivers diverge within the first three game frames (ring index and driver data),
then settle into two different states. This matches the much earlier observation that
the Z80 is released at frame 25 line 86 (recompiled) versus line 82 (interpreter): the
driver starts at a different phase and stays offset.

Next step: examine why the ring index is already 0x10 vs 0x00 at game frame 2 - i.e.
which 68K writes reached the ring before that point, and whether the driver's first
init pass ran at a different line within the frame.

### 2026-11-17: FIXED - the YM2612 timer A was never implemented

Instrumented the YM status path and counted status polls and timer-overflow flags:

```
recompiled : ym status reads 9245535, timer-B flag seen 0
interpreter: ym status reads 6014540, timer-B flag seen 0
```

Neither backend ever raised an overflow flag, while the driver polls the status register
millions of times - it was waiting for a timer that never fired. Logging the timer
programming showed which timer the driver actually uses:

```
[YMREG] f=227  reg=27 val=05
[YMREG] f=1516 reg=27 val=45
[YMREG] f=1628 reg=24 val=FE
[YMREG] f=1628 reg=25 val=01
[YMREG] f=1628 reg=27 val=55
```

Register $27 bit 0 (load/run timer A) and bit 2 (enable timer A flag) are set, and
$24/$25 program timer A - not timer B. The bus model in `runner/video/genesis_bus.c`
implemented only timer B (its comment says only B "is currently needed by supported
software", true for the Sonic titles and false for Shadowrun).

Implemented timer A following ymfm's formula (`ymfm_fm.ipp`: period = (1024 - TA) * 144
YM clocks, i.e. (1024 - TA) * 1008 master cycles at the 7:1 master/YM ratio the file
already uses for timer B's 16128 constant): register $24/$25 latches, bit 0 load/run,
bit 2 flag enable, bit 4 flag reset, status bit 0.

Result on the reference replay:

```
before: FM thirds [6570, 6570, 383, 383]     (music died in the first third)
after : FM thirds [6570, 6570, 6353, 4127]   (music continues through the session)
```

All six boot hashes unchanged (45E5/E29B/06B5/29F9/5F8D/11C1), the combat replay still
matches all 5042 inputs with an empty interior-label miss list, and two paced replays
produce bit-identical audio.

### 2026-11-17: intro scene pacing differs (reproduced without player input)

Built a deterministic reproducer for the reported "scene skips ahead" defect: an input
script (`build/pair.input`) drives the title screen and menu by itself, then samples a
screenshot plus a work-RAM dump every 20 frames. Running it on both backends and
matching frames by the game's own VBlank counter (`$FFF9EC`) shows the intro sequences
are NOT identical in game time:

```
game clock    recompiled        interpreter
  2059        30CDF648 (text)    47B7F03C (text, held ~80 frames)
  2193        3128F65B (ambush)  54847DB0 (text, held ~140 frames)
  2358        ...               170D2006 (text, held ~180 frames)
  2771        3087DFFF (frozen) 3128F65B (ambush)
```

So the recompiled build reaches the ambush text at game frame ~2190 while the
interpreter reaches it at ~2770: the cutscene advances faster per game frame in the
recompiled build. The content is not missing - the text cards pass much faster.

Supporting measurements:
- both backends consume the same nominal 68K budget (M68K_PER_LINE 488 x 262 =
  127856 cycles/frame, matching 7.67 MHz at 60 Hz)
- the generator charges `estimate_cycles_prm`, the same PRM model the shipping
  interpreter charges, so the difference is not the cost model in principle
- the game VBlank clock advances in bursts on both backends: over 200-frame windows the
  recompiled build advances by 173/200/200/182 and the interpreter by 200/200/199/174,
  so both drop VBlanks during scene transitions
- instruction-per-frame counters are not comparable (the recompiled build parks on its
  VBlank fast path instead of executing the wait loop)

Next: identify what paces the cutscene (the counter it waits on) and why it advances
sooner in the recompiled build; the park/fast-path and VBlank bookkeeping are the prime
suspects.

### 2026-11-17: port updated to SDK v0.1.3 (maintainer's sound-timer fix)

SDK v0.1.3 (`ae3e1df`) contains `18921ed Preserve running FM timer phase when clearing
its flag` - acknowledging a timer flag no longer restarts the timer's deadline. The port
was moved from `48e0f90` to `v0.1.3` and our local changes re-applied (one conflict in
`diagnostic_replay.c` resolved by taking the upstream file wholesale, since it rewrote
the checkpoint hashing and already includes the ignore-checkpoint bypass).

The same phase-preservation rule was applied to the timer A implementation added here
(previously every load/acknowledge reset the deadline).

Results on v0.1.3 + timer A:
- boot hashes 1000-6000 unchanged (45E5/E29B/06B5/29F9/5F8D/11C1)
- scripted session FM thirds [6570, 6570, 4822, 4566] - music plays throughout
  (before the timer A implementation: [6570, 6570, 383, 383])
- the intro scene-pacing difference is unchanged: at matched game clocks only 4 of the
  45 sampled frames share a screen hash between the recompiled build and the interpreter
  (10 screens appear only in the recompiled run, 8 only in the interpreter)

Note: v0.1.3 also changed the replay container format, so replays recorded with the
previous build (including the 20261115-204746 combat session) are rejected with
"invalid startup SRAM attachment". A replay re-recorded with the current build is needed
for replay-based validation; the deterministic input-script runs are unaffected.

### 2026-11-17: the VBlank-yield shortcut drops the ROM routine's side effects

The intro's scene driver (`$059F30` onwards) is a VBlank-paced loop that calls
`$000BD2` and counts the calls. The ROM routine is not the Sonic-style
`move #sr / tst.b flag / bne self / rts` idiom that the generator's yield shortcut
assumes:

```
000BD2  addq.w #1,$FFDF88      ; per-wait counter used by the game
000BD8  move.w $FFF9F6,d7
000BDE  cmp.w  $FFF9EE,d7
000BE4  beq.b  $000BDE         ; spin until the VBlank counter changes
000BE6  move.w $FFF9EE,$FFF9F6
000BF0  rts
```

`game.toml` listed `vblank_yield_addr = 0x000BD2`, so the generator replaced the whole
function with `g_cpu.SR = 0x2300; glue_yield_for_vblank();` - dropping the `addq.w` on
`$FFDF88` and the `$FFF9F6` bookkeeping entirely. Any game logic counting those waits
therefore advanced faster than the ROM.

Disabling the directive (so the real body runs):

- the game's VBlank clock now tracks the interpreter within 1 frame instead of drifting
  to 25 frames over the same window
- boot hashes change (45E5/E29B/06B5 -> 7258/EE92/64B0) - expected, because the dropped
  side effects now happen

The intro text-card duration still differs from the interpreter at matched game clocks,
so this is a real fidelity fix but not yet the whole scene-skip cause.

### 2026-11-18: scene skip FIXED - the vblank_yield shortcut dropped ROM side effects

Root cause confirmed. `game.toml` declared `vblank_yield_addr = 0x000BD2`, and the
generator replaces a declared wait function wholesale with
`g_cpu.SR = 0x2300; glue_yield_for_vblank();`. Shadowrun's routine is not the
Sonic-style `move/tst.b/bne self/rts` idiom the shortcut assumes:

```
000BD2  addq.w #1,$FFDF88      ; per-wait counter the game reads
000BD8  move.w $FFF9F6,d7
000BDE  cmp.w  $FFF9EE,d7
000BE4  beq.b  $000BDE
000BE6  move.w $FFF9EE,$FFF9F6
000BF0  rts
```

Dropping the `addq.w` and the `$FFF9F6` bookkeeping made every wait-loop in the game
complete sooner than the ROM allows, so VBlank-paced cutscenes advanced faster and the
intro jumped from the twilight card straight to the ambush.

Fix: remove the `vblank_yield_addr` directive so the real body executes.

Validation (deterministic input script: title -> menu -> intro, START only, screenshots
plus RAM dumps every 20 frames, matched by the game VBlank counter):

```
intro screens at matched game clocks: 45 / 45 identical to the interpreter
wait counter $FFDF88:                 within 2 counts across 2757 common game frames
music (FM thirds):                    7247 / 7247 / 4700 / 4876   (continuous)
boot hashes: 7258 / EE92 / 64B0 / D843 / 5F8D / 11C1  (frames 1000-4000 changed because
the dropped side effects now happen; 5000/6000 unchanged)
```

Methodology note: an earlier scripted reproducer used two `A` presses after START and
appeared to show the port skipping the text cards. Button presses advance the intro text
by design, and the presses landed at different game times in the two backends; with
START-only input the sequences are identical. Check the input script before concluding a
scene is skipped.

### 2026-11-18: intro text was dispatched through interior labels

The intro text plots are entered through computed jumps to blocks that sit *after* a
`jmp $c0da`, so the recompiler never made them function entries. The dispatch reported
them at run time:

```
[dispatch] interior-label miss: $05AEC6 inside func $000000 at frame 1595
[dispatch] interior-label miss: $05AEDA ... frame 1716
[dispatch] interior-label miss: $05AEEE ... frame 1897
[dispatch] interior-label miss: $05B378 ... frame 2138
```

`$05AEC6/$05AEDA/$05AEEE` load a string pointer and a VRAM destination and tail-call the
text plotter at `$00C0DA`; `$05B378` is the CRAM/VRAM transfer setup. Reached only by
call_by_address, they ran through the fallback, so the intro text never appeared.

Added them to `[functions].late_extra`. Verification (input script: title -> menu ->
archetype -> intro, screenshots plus RAM every 20 frames, matched by the game VBlank
counter):

- `interior_label_misses.toml`: empty
- intro screens identical to the interpreter: 45/45 (previously 11/45)
- the twilight card now renders ("The Time: January 31, 2058" over the skyline)

Remaining report from play: sound becomes "a mess" at the ambush without vanishing.
A pre-resample capture of that transition shows no clipping (0 samples at full scale) and
no dropouts (per-second RMS 380-2058), so it is a timing/voicing problem rather than
noise. The YM timer A only raises its status flag here; the Z80 IRQ line is still only
wired for VBlank (`genesis_machine.c` asserts it at V-int), which is the next thing to
check if the driver expects an interrupt rather than polling.

### 2026-11-18: YM timer overflow now sets the flag unconditionally and raises the Z80 IRQ

The timer model set the status flag only when the register-$27 enable bit was set, and
never raised the Z80 interrupt at all (only the V-int was wired, in
`genesis_machine.c`). On the real chip the overflow always sets the flag and the enable
bit gates the interrupt, so a driver that counts timer ticks saw them late and could miss
them - consistent with music that races and loses its melody.

Changed:
- timer A and timer B overflow set their status bit unconditionally
- the enable bits (`$27` bit 2 / bit 3) gate `ym_raise_z80_irq()`, which asserts the
  same `int_pending` path the V-int uses (`z80_recomp_assert_irq` in recomp builds)

Verified: boot hashes unchanged (7258/EE92/64B0/D843/5F8D/11C1 - audio timing does not
affect the video state), music continuous (FM thirds 6604/6604/3911/4009), and a
pre-resample capture of the intro-to-ambush transition shows no clipping, no large
sample discontinuities and a musical onset rate (~5.5/s) in both FM and PSG.

### 2026-11-18: FM timers advance on the schedule, not on polls

Instrumented the timer: Shadowrun's driver loads timer A with TA=0, i.e. period
(1024 - 0) * 1008 = 1,032,192 master cycles = 52.0 Hz - a music-tempo tick. The model was
lazy: it only evaluated the timer when the Z80 read the status register or wrote the YM,
and each call collapsed every elapsed period into a single event. Measured rate: 8.1
fired-but-coalesced events per second instead of 52, so a driver counting ticks could not
keep time (fast/uneven tempo, garbled output once several voices are active).

Fix: `gbus_ym_timer_service()` is called once per scanline from the machine loop with the
absolute master-cycle stamp, and delivers one flag + interrupt per elapsed period (bounded
catch-up). The lazy status-read path uses the same loop, so it stays consistent.

Measured after the change: 2059 timer events over the 39.6 s the timer is loaded =
**52.0/s**, exactly the chip rate (previously 8.1/s). Boot hashes unchanged
(7258/EE92/64B0/D843/5F8D/11C1); FM thirds 5848/5021/3996 (continuous); no clipping,
no sample discontinuities.

### 2026-11-18: the timer interrupt doubles the sequencer rate

Measured the driver's own register traffic: it loads timer A with `$27 = $05` (bit 0 load,
bit 2 IRQ enable) and never writes `$24`/`$25`, so the chip's period is TA=0 -> 1024 * 1008
master cycles = 52 Hz. That rate is correct for the hardware.

What is not settled is the interrupt. With the Z80 IRQ raised once per timer period the
driver's note rate increases by ~52%:

```
timer IRQ off: key-ons 18.66/s
timer IRQ on : key-ons 28.36/s     (timer firing at 46.6/s either way)
```

Both backends agree with each other when the IRQ setting is the same (mean gap between
notes 1.75 frames in each), so this is a model question, not a recompiler question.

`GENESIS_YM_TIMER_IRQ` now gates that interrupt (default off, flag always set). Remaining
question: whether the driver expects the 52 Hz interrupt (as its `$27` write suggests) or
polls the flag, and whether our delivery acknowledges the chip's flag the way the handler
does. That determines the correct tempo.

Also relevant: the track itself is chosen by the game's RNG, whose seed is a checksum of
work RAM at boot, so the port can legitimately play a different track than a given
playthrough video. For A/B comparison both backends were run with `GENESIS_FORCE_SEED`.

### 2026-11-18: crackle is a real-time starvation, not synthesis

Measured with `GENESIS_FRAMETIME_LOG` (CPU per frame) over the intro + ambush script:

```
mean 17.0 ms/frame, median 17.0 ms, p95 17.0 ms, max 102 ms
budget for 60 fps: 16.68 ms
wall-clock: 2600 frames in 44.55 s = 58.4 fps
```

The FM and PSG streams themselves are clean in a pre-resample capture (no clipping, zero
large sample discontinuities, correct 888.7 FM samples/frame), so the crackle comes from
the device path concealing a continuous ~2.6% audio shortfall, plus long hitches (up to
100 ms) at scene loads.

Also measured, for the tempo question:
- driver loads timer A via `$27 = $05` (load + IRQ enable) and never writes `$24`/`$25`,
  so the chip period is TA=0 -> 52 Hz; our scanline service now delivers 52.0 f/s
- raising the Z80 timer interrupt inflates the driver's note rate by ~52 %
  (18.7 -> 28.4 key-ons/s); it is therefore opt-in (`GENESIS_YM_TIMER_IRQ`) and off
- with the interrupt off, port and interpreter agree on note timing (1.75 frames/note)

Next: reduce per-frame cost to get under 16.68 ms (or shorten the load hitches), since
the audio starvation is a consequence of running below the frame rate.

### 2026-11-18: the crackle was the audio bridge repeating frames

Profiling corrected an earlier assumption: per-frame work is only ~2.4 ms (machine 1.6,
audio drain 0.7, replay 0.1), not the 17 ms I had measured earlier - that number was the
paced wall-clock frame, not CPU. There is no starvation.

The bridge's own counters (GENESIS_AUDIO_BUFFER_TRACE) showed the real source:

```
real device, default buffer: callbacks=1194 conceals=1 repeated=9235 underruns=0 overflows=0
```

`repeated` is the DRC bridge's pitch-preserving stall concealment: ~9k frames of audio
replayed to cover producer jitter, which is what sounds like crackle and swallowed notes.

Raising the buffer slack removed it entirely:

```
device samples 1024 -> 2048, preroll 200 ms -> 350 ms
callbacks=591 conceals=0 repeated=0 underruns=0 overflows=0
```

### 2026-11-18: the fight itself cannot be reached without input

A 11000-frame scripted run (title -> menu -> archetype -> intro, then 9000 frames of no
input) shows the music playing until ~98 s (ambush window, peaks ~11000) and then silence
from ~100 s onward: the game parks on the ambush card waiting for input, and the Z80
idles in its wait loop (`pc $0041/$0062`) while the frame counter keeps advancing.

The host-rate stream across that whole run has no clipping, no discontinuities and no
dropouts, so the crackle the player reports in the fight is not reproducible headlessly -
it needs a recorded session that carries the player's inputs through the battle.

Session recording: `scripts/record-session.ps1` (writes replay, audio and RAM; the same
mechanism produced the 20261115-204746 combat session used earlier).

### 2026-11-18: session recorded; the failing sounds are the DAC/PCM path

The player recorded the failing run (`sessions/20261118-071737`, 2897 frames, 21 scenes;
the ambush is the tail). Their description identifies the missing sounds precisely:
drums and character death voices - i.e. the YM2612 channel-6 **DAC/PCM**, not FM music.

Measured on that session and on scripted runs:

- FM music path is clean (no clipping, no discontinuities, healthy levels through the
  ambush window)
- DAC register ($2A) traffic reaching the synth is **1 write per frame** (685-1837
  writes per run), not the thousands-per-second a PCM stream needs - the drums/voices are
  effectively never streamed
- the same low DAC rate appears in every scenario that reaches the ambush text; the
  fight itself (where the voices play) has not been reached headlessly because scripted
  input only navigates the character-creation menus

Replay of the recorded session worked immediately after recording ("all 2897 recorded
executions matched") but is rejected after the next rebuild with `invalid startup SRAM
attachment`: the recorder stores the post-play SRAM as the `.sav` sidecar, while the
replay's boot snapshot expects the startup SRAM. Next step is to fix that recorder/loader
mismatch (or archive the startup SRAM), then instrument the DAC path against the fight.

### 2026-11-18: PCM (drums/voices) restored - timer A reload + interrupt

The player's report (drums and death voices missing) identified the DAC/PCM path. Two
model bugs kept it silent:

1. **Timer A was never reloaded with a new period.** Shadowrun arms timer A with TA=0
   (52 Hz) during the intro and re-programs it to `$24=$FE,$25=$01` (period 7 * 1008 =
   7056 master cycles = 7609 Hz, a PCM rate) when the ambush starts, writing
   `$27=$55` (load + enable + flag reset). Our phase-preservation rule ignored the new
   period because the timer was already running, so it stayed at 52 Hz.
   Fix: a load written together with the flag reset (bit 4), or with a changed period,
   restarts the timer with the new value; a plain acknowledgement still preserves phase.

2. **The timer interrupt was disabled by default.** The driver streams one DAC byte per
   timer interrupt, so with the interrupt off it managed one byte per frame.

Measured with both fixed (ambush window):

```
                   intro key-ons   ambush DAC bytes   ambush key-ons
IRQ off (before)      28.71/s            36/s             4.99/s
IRQ on  (after)       28.71/s          1730/s            16.15/s
timer period          1032192 (52 Hz)   -> 7056 (7609 Hz)
```

The intro music rate is identical either way (28.71 key-ons/s), so the earlier "tempo
too fast with the interrupt" symptom was the broken reload, not the interrupt. The timer
interrupt is now on by default; boot hashes are unchanged (7258/EE92/64B0).

### 2026-11-18: PCM works without inflating the music tempo

The driver's IRQ handler is six bytes long: it stores SP into `$003E` and returns, so the
main loop treats **every interrupt as one tick**. Delivering a timer interrupt per PCM
sample therefore also drove the music clock: the in-game note rate rose from 6.5/s to
17.5/s and stayed fast because the driver leaves timer A at a PCM rate (7056/10080/6048
cycles) after the ambush.

Measured split with the interrupt gated to actual PCM activity:

```
                    key-ons      DAC bytes     timer IRQ
intro (music)       9.65/s          0/s            0/s
ambush (PCM)       46.97/s       5196/s         5537/s
after              9.83/s       1474/s         1587/s
```

So the music clock is back to its polling rate while the DAC stream runs at ~5 kHz.
Boot hashes unchanged (7258/EE92/64B0).

### 2026-11-18: PCM restored; drum pattern still runs fast (poll-driven)

Status after the PCM fixes: all sounds play (player-confirmed), regular music tempo is
correct, but the drum pattern in the ambush runs too fast (rhythm, not pitch).

Tested whether the pattern clock is the timer interrupt: halving the delivered interrupts
(GENESIS_YM_IRQ_DIV=2) changed nothing - IRQs 5537 -> 2768/s, DAC bytes unchanged at
5196/s, drum tempo unchanged. So the driver advances its pattern from **polling the YM
status**, not from the interrupt.

The likely mechanism: our timer A status bit stays set for the whole period and is only
cleared when the driver writes `$27` (observed about once per frame). A driver that polls
the bit in a tight loop therefore sees "tick" on many consecutive polls instead of once
per period, so its pattern counter advances far too often.

Earlier evidence fits: the Z80 performs millions of status reads per run, and the
timer-B flag was never observed set at a read, i.e. everything is polled.

Next step (definitive): disassemble the uploaded Z80 driver to see what the pattern counter
is driven by. The driver lives in Z80 RAM (not ROM); a mid-run dump is saved at
`build/z80_driver_1700.bin`, entry `$08C3`, IRQ vector `$0038` (a 6-byte
`LD ($003E),SP; RETI` that the main loop uses as a tick). A Z80 disassembler is not
available in this environment (capstone build lacks Z80), so that is the first thing to
provision.
