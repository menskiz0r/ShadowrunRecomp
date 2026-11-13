# SDL front-end (playable build)

The CMake build produces the same kind of executable as the other
segagenesisrecomp game projects: the framework's SDL runner plus this game's
`GameSpec`.

```powershell
cmake -S . -B build -G "MinGW Makefiles"
cmake --build build -j
build\ShadowrunRecomp.exe "game\shadowrun.bin"
```

Verified on this machine:

```
[VIDEO] window 640x448 (4:3)
[VIDEO] renderer name=direct3d11 vsync=1
[audio] DRC bridge: 223721 Hz internal -> 48000 Hz device (preroll 200 ms, conceal on)
[pacer] target frame rate: 59.9401 fps
[SRAM] loaded 16384/16384 bytes from ...\shadowrun.srm
[rewind] 60 snapshots, interval 6 (6.0 seconds)
[feedback-replay] ...\Shadowrun-feedback.replay (default on)
```

So the window, renderer, audio device, frame pacing, SRAM load, rewind and
feedback replay all come from the framework and work here.

## Scripted runs

The runner accepts a frame-timeline input file, which makes automated runs
possible without a keyboard:

```
build\ShadowrunRecomp.exe game\shadowrun.bin ^
  --input-script scripts\shadowrun-flow.input ^
  --measure-runtime 30000 --runtime-uncapped
```

`--measure-runtime N --runtime-uncapped` runs N frames as fast as the host allows
(without it the runner is locked to 59.94 fps wall time, so a 24 000-frame route
takes seven minutes).

`scripts/shadowrun-flow.input` is the current best route: boot, menus, archetype,
intro, hotel, checkout dialogue, Pocket Secretary, then a save attempt. It uses
`SCREENSHOT` at each checkpoint and `EXIT 0` at the end, so a run is
self-documenting.

## Menu mapping (what the sweep showed)

A scripted sweep (screenshot + `DUMP_RAM` at each step, a screenshot captured during validation (not distributed))
records the actual sequence on this build:

| Step | Screen |
|---|---|
| after START | Pocket Secretary page ("a steaming mug of soykaf") |
| press A | back to the room's **Hotel Options** menu (Karma Screen / Check Out) |
| RIGHT, RIGHT, RIGHT | hotel menu unchanged |

So on the SDL runner START toggles the Pocket Secretary, and any button closes it
back to the room menu (second sweep, a screenshot captured during validation (not distributed): B, START,
RIGHT and DOWN all return to the hotel menu and move its cursor).

Critically, the sweep shows the run never *leaves* the hotel room: the room menu
offers "Karma Screen / Check Out", which is the pre-checkout state. The headless
route's Down+A reaches checkout; here the same input lands while a dialogue is
still active, so checkout never fires and the save menu is never reachable.

That makes the remaining work a route problem, not a tooling problem.

### Correction pass (exact headless deltas)

The first SDL script was a bad conversion: it dropped the ninth A press (frame
9700), so every later input landed 300 frames early, mid-dialogue. Re-running with
the timeline copied verbatim from the validated headless route
(a screenshot captured during validation (not distributed)) gives:

| Checkpoint | Screen |
|---|---|
| 14 600 | hotel checkout dialogue with the manager (as expected) |
| 17 000 START | Pocket Secretary page ("steaming mug of soykaf") |
| RIGHT | character sheet |
| A | karma upgrade screen |

So the two builds still differ in *which* status page START opens, even with
identical inputs — the game's menu state depends on whether checkout completed.
The headless route enters the status panel on a different page and reaches the
Pocket Secretary menu with A after seven RIGHTs; here START already lands on the
Pocket Secretary and A opens the karma screen instead.

Reconciling that needs the checkout to complete first, which needs the dialogue
choice timing (14600) re-measured on the SDL side. This is the same iterative
route-building the headless flow needed; it is bounded but not quick.

### Why frame-numbered routes are fragile here

`input_script.h` states the timeline is "executed once per wall frame", while the
game consumes simulated frames. Those two counters separate whenever a frame takes
longer than the vsync interval (ROM load, disc/IO stalls, host scheduling):

* uncapped run (`--measure-runtime N --runtime-uncapped`): the first screenshot
  landed at frame 9101 instead of 9400 — inputs were ~300 frames early in
  simulation time;
* real-speed run: the same checkpoint landed at 22301 instead of 21400 — inputs
  were ~900 frames late.

Same script, same build, different alignment. A route built on frame numbers
therefore cannot be stable on this runner; only state-keyed directives are.
`WAIT_RAM8` / `ASSERT_RAM8` exist for exactly that reason, and the menu state ids
in `$FFE2xx` are the handles. The missing piece is the id for the Save/Load screen
itself, which would have to be found by dumping RAM there.

For reference, the other projects' test suites (`tests/run_tests.py`,
`_smoke.bat` in the Sonic and RKA repos) do not ship a scripted save route either;
they assert structural things (frame hashes, coverage) rather than drive menus. The RAM dumps show the menu state block
at `$FFE2xx`:

| address | hotel menu | Pocket Secretary |
|---|---|---|
| `$FFE231` | 2 | 0 |
| `$FFE241` | 4 | 0 |
| `$FFE245` | 1 | 4 |
| `$FFE24A` | 7 | 0 |
| `$FFE267` | 12 | 0 |

Those are stable over time within a state, so `WAIT_RAM8` can key off them
(`WAIT_RAM8 FFE231 0` really does block until the Pocket Secretary is up — the
sweep script used it successfully). What is still missing is the id for the
Save/Load screen itself.

## Timing calibration status

**Not finished.** The headless harness and the SDL runner do not count frames
identically, and the menu state machine advances differently depending on when
the inputs arrive:

* at frame ~14 000 the SDL build is in the hotel dialogue (as expected);
* pressing START there lands in the Pocket Secretary on one run, and the hotel
  options menu on another, depending on the exact frame;
* consequently the scripted save has not yet produced `shadowrun.srm` on the SDL
  build. Saving itself is proven on the headless build (14/14 edge cases in
  `validate-saves.ps1`).

Doing this properly needs RAM-state assertions (`WAIT_RAM8` / `ASSERT_RAM8` in the
input-script language) rather than screenshot guessing: the game's mode and menu
selection live in work RAM, so a route can wait for a state instead of guessing a
frame number.

## Division of labour (current)

| Build | Role |
|---|---|
| `ShadowrunRecomp.exe` (this page) | the playable game: window, input, audio |
| `shadowrun_runner.exe` (headless) | the assertion vehicle: deterministic frames, BMP/WAV capture, coverage and leak checks |

Both are built from the same `game/game.toml`, the same generated code and the
same `GameSpec`, so the evidence gathered on the harness applies to the game.

## STOP #imm and the fiber runner (fixed 2026-11-13)

`genesis_stop_until_interrupt()` is game-supplied: the framework declares it but
never defines it (searching `runner/` finds only the header declaration). The
first implementation here did

```c
g_cpu.SR = sr_imm;
glue_wait_vblank_done();   /* WRONG on this runtime */
```

`glue_wait_vblank_done()` is a **no-op** on the fiber runner ("In single-threaded
Step 2, not needed - main loop drives everything", `glue.c`), so STOP fell through
instead of halting the 68K until the next interrupt. On screen that looks like the
logo appearing and then the game restarting.

The runtime's own interpreter shows the intended contract (`glue.c`, convergence
for `GENESIS_COSIM_WAITVBL_PC`):

```c
g_cpu.SR = 0x2300u;
glue_yield_for_vblank();
```

so the handler now sets SR and yields to the vblank fiber (`glue_yield_for_vblank`
is declared in `genesis_runtime.h`).

Debugging note: `runner_write_screenshot_file()` produced all-black PNGs in this
environment regardless of renderer (software, opengl, direct3d, direct3d11), while
the simulation was provably healthy - work RAM at frames 3 000 and 6 000 matched
the validated headless run at 95 %. Do not judge this build by its screenshots.
