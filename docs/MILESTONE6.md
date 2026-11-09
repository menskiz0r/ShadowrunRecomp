# Milestone 6 — audio ✅

The YM2612 is no longer stubbed: the game's music and sound effects are
synthesised by the real **ymfm** chip model, driven by the game's own Z80 sound
driver.

## Why it was silent

The framework's YM2612 is **C++** — `runner/audio/ym2612_ymfm.cpp` plus
`fm_shadow.cpp` on top of `runner/external/ymfm/src`. The headless runner was
built with `gcc` only, so those files were never compiled and a silent stub was
linked in their place.

Fix: compile the ymfm sources and the two wrappers with `g++ -std=c++17`, drop
the stubs, link with `g++` (for libstdc++). Runner grew 3.66 MB → 4.77 MB.

## Measured output

The adapter now feeds the framework's `GenesisSimAudio` buffers and measures what
comes back:

```
audio: frames_with_samples=21000  fm_peak=7835  psg_peak=8182
```

Every frame produced samples from both chips. Energy over a full play-through:

| Time | Content |
|---|---|
| 3–6 s | SEGA logo chime (peak ≈ 3600) |
| 14–35 s | **title/menu music** (continuous, RMS ≈ 950–1850) |
| 84 s+ | in-game cues |

Excerpts (16-bit stereo, 53,267 Hz — the YM2612's native rate). **These are
captured game audio and are kept local only, not in the repository** (see
`M9-REPO-PLAN.md`):

* `../build/evidence/sega-chime.wav` — the boot jingle
* `../build/evidence/title-music.wav` — 20 s of title music

Regenerate with `DSH_WAV=out.wav shadowrun_runner.exe "<rom>" 3000`.

## Reproduce

```
DSH_WAV=out.wav shadowrun_runner.exe "Shadowrun (U) [!].bin" 3000
```

writes every mixed frame to a WAV (`audio:` line reports peaks). The build script
now compiles the C++ audio path automatically.

## Notes

* The mix has a constant DC offset (~380 LSB) when a sound is not playing; the
  waveforms themselves are correct (the chime and music show proper peaks). Worth
  a look when polishing, but it does not affect audibility.
* Output rate is the chip's native 53,267 Hz; a 44.1/48 kHz resample belongs in
  the final host (SDL audio callback) rather than in the emulation path.

## Next

* **M7 — saves**: SRAM is modelled by `machine_save_state` / the bus SRAM window
  but never persisted to disk.
* **M8 — publishable repo**: clean build docs, no ROM/assets, validation script.
