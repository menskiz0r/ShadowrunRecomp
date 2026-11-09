# Credits

This port exists because of other people's work. Nothing here would run without
it.

## The framework — Matthew Stanley ([@mstan](https://github.com/mstan))

[**segagenesisrecomp**](https://github.com/mstan/segagenesisrecomp) is the whole
engine of this project: the 68000 static recompiler, the generated-code runtime,
the VDP (planes, window, sprites, DMA), the Z80 and YM2612 audio path, the bus
and scheduler, SRAM handling, and the SDL front-end.

Its companion repos are used as well:

| Repo | What it provides here |
|---|---|
| [segagenesisrecomp](https://github.com/mstan/segagenesisrecomp) | recompiler, runner, runtime, audio, video |
| [m68k-recomp-core](https://github.com/mstan/m68k-recomp-core) | Genesis 68000 code generation and proof passes |
| [z80-recomp-core](https://github.com/mstan/z80-recomp-core) | Z80 runtime helpers |

The colour output uses the framework's hardware DAC ladder, which its author
verified channel-for-channel against BlastEm's `vdp.c`.

Two bugs found while building this port were reported upstream with reproducers
and patches: [m68k-recomp-core#14](https://github.com/mstan/m68k-recomp-core/issues/14)
and [segagenesisrecomp#71](https://github.com/mstan/segagenesisrecomp/issues/71).

Part of the R.A.I.D. / RetroPortingToolkit community.

## Libraries

* **ymfm** — Aaron Giles' YM2612/OPN FM synthesis library (BSD-3-Clause).
* **clowncommon**, **minicoro**, **superzazu**, **xxhash** — bundled by the
  framework: common types, fibers, Z80 helpers, hashing.
* **SDL2** — window, input and audio (zlib licence).

## Reference and tooling

* **BlastEm** — the framework's oracle for VDP colour levels.
* **BizHawk 2.11.1** — reference emulator used for the frame comparisons in
  `docs/MILESTONE8.md`; its Lua scripting made automated capture possible.
* **Dr. Memory** — memory checking, used as far as this Windows build allows.
* **w64devkit** — the GCC toolchain these builds use.

## Game

*Shadowrun* (Sega Genesis, 1994) is © SEGA / The Topps Company; the setting and
trademarks belong to their respective holders. This project contains no game
code, art, audio or saves, and requires the user's own cartridge dump. It is not
affiliated with or endorsed by any rights holder.
