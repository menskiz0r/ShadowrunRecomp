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
