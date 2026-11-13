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
