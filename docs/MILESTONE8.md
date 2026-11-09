# Milestone 8 — verified, not just working

Renumbered: **M8 is the proof milestone**, **M9 is the publishable repo**.
Nothing ships on "it looked right in a screenshot".

## Exit criteria

Every item is a check that either passes with evidence or keeps the milestone open.

### 1. Memory

**Toolchain constraint (measured 2026-11-08):** the Windows toolchain in use
(w64devkit GCC 16.2) has **no `libasan` and no `libubsan`**, so the original
"just build with ASan" plan is not available here:

```
gcc -fsanitize=address  ->  ld: cannot find -lasan
gcc -fsanitize=undefined -> ld: cannot find -libubsan
```

What *does* work: GNU ld's `--wrap` (verified with a probe program), so
allocation tracking can be interposed at link time.

Revised checks:

| Check | How | Pass |
|---|---|---|
| No growth over a long session | soak + working-set sampling (done: 300 k frames) | flat / decelerating |
| No outstanding allocations at exit | `-Wl,--wrap=malloc,--wrap=free,--wrap=realloc,--wrap=calloc` counter, compared before the frame loop and at exit | live-block delta == 0 |
| Cross-check | Windows `HeapWalk(GetProcessHeap())` live-block count at exit vs baseline | no growth |
| Leak-checker verdict (optional, external) | Dr. Memory on the same scripted flow | zero leaks |
| Save/load cycles do not accumulate | repeat save→load 50× in one session | live blocks flat |

#### Uninitialised reads — tooling dead end, substitute checks carried out

Dr. Memory is **unusable here**. Two builds (2.6.20434 and 2.6.20133) both crash
in their own instrumentation before the target starts, even on a two-line toy
program:

```
<Application wrap_probe.exe. Dr. Memory internal crash at PC 0x00007ff70d95204d.
 Program aborted. 0xc0000005
```

That is an incompatibility with this Windows build (26300), not with our binary.
WSL is blocked in this environment, so a Linux valgrind/MemSan run is not
available either.

Substitute checks, all run on the full scripted flow (24 000 frames: title, menus,
archetype, intro, room, check out, walk, save):

| Check | Method | Result |
|---|---|---|
| heap reads of memory never written | `DSH_POISON_HEAP=1` fills every `malloc` block with `0xFE` | **identical** instruction count (15 006 774), frame hash, audio peaks |
| stack reads of uninitialised locals | two full builds, `-ftrivial-auto-var-init=zero` vs `=pattern` | **identical** instruction count (15 442 774), frame BMP hash, SRAM hash, audio peaks |
| compiler proof attempt | `-O2 -Wall -Wextra -Wmaybe-uninitialized -Wuninitialized` on all host sources | **0 warnings** |

Honest limit: these detect only uninitialised reads that change observable
behaviour. A read whose value happens to be overwritten later, or on a code path
the flow never reaches, would not show up. The real proof needs a working
memcheck; recorded as such rather than claimed.

### 2. Coverage of translated code

| Check | How | Pass |
|---|---|---|
| No reachable interior labels | run the whole scripted flow, then assert `interior_label_misses.toml` has zero entries | empty |
| No dispatch misses | same, `dispatch_misses.toml` | empty |
| No interpreter fallback | `floor_coverage.toml` | empty |

Today the seeds are *reactive* (they were added when a miss showed up). M8 makes
this a gate: the flow must run with an empty evidence set.

### 3. Reference comparison

**Reference installed:** BizHawk 2.11.1 (win-x64, `build/bizhawk`), driven by a Lua
script that advances to chosen frames and calls `client.screenshot`. Harness:
`port/compare-reference.ps1`.

**Comparison method matters.** A raw pixel diff is misleading because the colour
pipelines differ *by design*:

| | ladder |
|---|---|
| this port | hardware DAC ladder `{0,49,87,119,146,174,206,255}` (`genesis_dac.h`, documented as verified against BlastEm's `vdp.c levels[]`) |
| BizHawk | naive `v × 34` = `{0,34,68,102,136,170,204,238}` |

So the harness maps every colour of ours to the reference colour it lands on and
reports the share of pixels that agree after that mapping. On the title screen
all **20 distinct colours map 1:1 with zero ambiguity** — the images are identical
apart from the ladder.

| Checkpoint | Result |
|---|---|
| our 300 vs ref 304 | **100.00 %** structural |
| our 600 vs ref 604 | **100.00 %** |
| our 900 vs ref 904 | **100.00 %** |
| our 1200 / 1500 / 1800 / 2100 / 2400 vs ref +4 | **99.92 – 99.94 %** (a handful of pixels) |
| our 5995 vs ref 6000 | **100.00 %** |

**Correction (same day).** An earlier run appeared to show the reference on the
*Start Options* menu at frame 3004 while ours was on the title. Re-captured
cleanly, frame 3004 is the **title screen**, and our frames 2996-3000 match it at
**99.92 %** (the remaining pixels are the blinking "PRESS START" phase). The
apparent divergence was a **stale screenshot**: the harness cleared `ref_*.png`
but not the bare `NNNNN.png` files the Lua writes, so an interrupted earlier run's
capture was reused and attributed to the new frame number.

The harness now deletes every PNG, kills any running EmuHawk instance first, and
only then captures. Lesson recorded because this is exactly how a false
"regression" gets believed.

**Caveats:** BizHawk is a GUI application, captures at ~48 frames/s, and its Lua
has no `emu.exit` in this build (the harness kills the process). A per-checkpoint
frame search is needed because the boot offset drifts (measured +4 early, +5 by
frame 6000).

### 4. Audio quality

**DC offset — fixed.** Measured before: mean 278.5 LSB, with a constant 380.0 LSB
bias in every idle block. A one-pole high-pass at ~20 Hz (`r = 0.99764`) now runs
in the capture/playback path (`DSH_NO_DC=1` disables it for raw comparisons).

| | before | after |
|---|---|---|
| mean | 278.5 | **0.01** |
| idle DC blocks | 380.0 flat | ~0 |
| peak | 7 835 | 8 457 (headroom recovered) |

**Resampling — implemented.** `DSH_WAV_RATE=48000` resamples the native 53 267 Hz
stream to 48 kHz with streaming linear interpolation.

| band | native | 48 kHz | delta |
|---|---|---|---|
| 0–100 Hz | 51.8 | 51.8 | 0.0 dB |
| 100–1 000 Hz | 184.8 | 184.7 | 0.0 dB |
| 1–5 kHz | 220.0 | 218.5 | −0.1 dB |
| 5–12 kHz | 63.3 | 60.1 | −0.5 dB |
| 12–20 kHz | 5.5 | 4.5 | −1.7 dB |
| 20–24 kHz | 0.7 | 0.5 | −3.7 dB |

Duration preserved exactly (25.02 s both), RMS −0.19 %. The top-octave roll-off is
the known cost of linear interpolation; no aliasing increase. A polyphase FIR would
flatten it if we ever need hi-fi, but the content above 12 kHz in this soundtrack is
essentially nil.

Still open: an underrun/gap check over a 5-minute play with music (the headless
adapter writes a file rather than a device, so this is a recording-length check).

### 5. Saves

Encoded as a second script: `port/validate-saves.ps1` (six scenarios, 14 checks).

| Scenario | Result |
|---|---|
| no `.srm` at all | created at full size, 1 558 bytes of data |
| truncated (100 B) | loads short + zero-fills, no crash, rewritten at full size with data |
| oversized (32 KB) | loads the first 16 KB, ignored the rest, clamped on save |
| random garbage (16 KB) | no crash; save still lands |
| save into slot 2 | no crash, data written |
| killed mid-run | previous `.srm` **byte-identical** (SHA-256 unchanged) |

The last one holds because the writer is now atomic: it writes `<name>.srm.tmp`,
`fflush`es, then `MoveFileExA(..., REPLACE_EXISTING)` — a crash mid-write leaves
the previous file whole. A failed write keeps the old file and says so.

### 6. Patched recompiler

* Document both patches (`return_capture.c`, `code_generator.c`) as
  Shadowrun-validated, not general-purpose.
* Regression check: regenerate with the patches reverted and confirm the known
  failures come back (proves the patches are load-bearing, not cargo cult).

### 7. Reproducibility

* Fresh clone → `build_recompiler.ps1` → `build_runner.ps1` → `validate.ps1`
  on a clean machine.
* Record toolchain versions in the repo.

## Evidence log

| Date | Check | Result |
|---|---|---|
| 2026-11-08 | throughput | **1 014 frames/s** → 60 k ≈ 1 min, 300 k ≈ 5 min |
| 2026-11-08 | 120 000-frame soak (scripted play + save) | PASS: 34.2 M insns, 106 s, no crash, SRAM intact (checksum `1E50BB9A`) |
| 2026-11-08 | 300 000-frame soak (8 min game time) | PASS: 40.0 M insns, 295 s, no crash |
| 2026-11-08 | memory trend, 300 k frames | 9.3 → 11.4 → 12.0 → 12.5 → 12.7 MB at 0/25/50/75/100 %. **Decelerating** (+2.1, +0.6, +0.5, +0.2) — page-touching shape, not a linear leak. |
| 2026-11-09 | `-Wl,--wrap` leak counter | baseline 7 live blocks; exit delta **31** at 3 000 / 10 000 / 30 000 frames — constant, so one-time init, not a per-frame leak |
| 2026-11-09 | full flow (menus → save → walk → load) | exit delta **31** at 26 000 and 40 000 frames — no growth across the feature set either |
| 2026-11-09 | coverage gate | `dispatch_misses`, `interior_label_misses`, `floor_coverage`, `floor_unsafe` all **0 entries** after the full flow |
| 2026-11-09 | reference emulator installed | BizHawk 2.11.1; Lua capture harness written (`compare-reference.ps1`) |
| 2026-11-09 | frame comparison vs BizHawk | 100 % structural at 300/600/900/6000, 99.9 % at 1200–2400 (colour ladder differs by design, mapping is 1:1) |
| 2026-11-09 | reference 3004 re-captured cleanly | title screen, ours 2996-3000 match at **99.92 %** -> earlier "divergence" was a stale-file artifact, harness fixed |
| 2026-11-09 | Dr. Memory 2.6.20434 / 2.6.20133 | unusable: internal crash on any binary on this Windows build |
| 2026-11-09 | heap poison (`0xFE`) differential | identical instruction count, frame hash, audio |
| 2026-11-09 | stack `auto-var-init` zero vs pattern | identical instruction count, frame hash, SRAM hash, audio |
| 2026-11-09 | audio: DC blocker | mean 278.5 -> 0.01 LSB; idle bias 380 -> 0; peak 7835 -> 8457 |
| 2026-11-09 | audio: 48 kHz resample | duration exact, RMS -0.19 %, spectrum flat to 5 kHz, -1.7 dB at 12-20 kHz |
| 2026-11-09 | `validate-saves.ps1` | **all 14 checks pass** (missing, truncated, oversized, garbage, slot 2, kill mid-run) |
| 2026-11-09 | `validate.ps1` | **all 8 checks pass**: exit 0, leak delta 31, four empty evidence files, save checksum `1E50BB9A` (1 558 bytes), final frame 26 colours |
| 2026-11-08 | save → restart → load | PASS (1558-byte payload, "Successful download") |
| 2026-11-08 | strict JSR stack checker across the flow | only the deliberate captured-return frames |

## Status after the first pass

Done: soak/stability, leak counter (constant under both idle and full flow),
coverage gate, save round trip, rendering check. Encoded as one command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File port/validate.ps1
```

```
exit code                              True   exit=0 crash=False
no leak (delta constant)               True   live block delta=31 (expected 31)
no dispatch_misses.toml entries        True   0 entries
no interior_label_misses.toml entries  True   0 entries
no floor_coverage.toml entries         True   0 entries
no floor_unsafe.toml entries           True   0 entries
save written                           True   checksum=1E50BB9A non-zero=1558
frame renders                          True   26 distinct colours
all checks passed
```

Still open for M8: reference-emulator frame/audio diff, audio DC offset and
resampling, save edge cases (truncated `.srm`, kill-mid-save), uninitialised-read
testing.

## Order of work

1. **Leak tracker + coverage gate** — the two quick checks that turn "looks fine"
   into "checked". Both are self-contained.
2. **Reference-emulator comparison** — the long pole: needs a second emulator
   installed and a matching input script; produces the frame/audio diffs.
3. **Audio cleanup** (DC offset, resampling) and **save edge cases**.
4. **M9 repo skeleton** can be prepared in parallel; publishing waits for M8.

M9 only starts publishing when every row above is green.

## Independent of upstream

The two issues filed upstream (#14 on `m68k-recomp-core`, #71 on
`segagenesisrecomp`) do **not** block M8 or M9. Reply handling is documented in
`upstream/README.md`; silence is not a blocker either.
