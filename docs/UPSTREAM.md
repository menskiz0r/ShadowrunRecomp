# Upstream research — `mstan/segagenesisrecomp`

Research date: **2026-11-08**. Sources: GitHub API (repo metadata, contents, pull
requests, issues), raw files on `master`, and the two core submodule repos.

## Repository facts

| | |
|---|---|
| Repo | <https://github.com/mstan/segagenesisrecomp> |
| Description | Sega Genesis / Mega Drive game static recompiler ecosystem — part of the R.A.I.D. community |
| Licence | [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0) (`LICENSE.md`), plus [additional permissions](https://github.com/mstan/segagenesisrecomp/blob/master/PERMISSIONS.md) |
| Recompiler licence | `LICENSE-recompiler` — PolyForm Noncommercial 1.0.0, © 2026 Matthew Stan |
| Created / last push | 2026-03-25 / 2026-11-07 |
| Stars / forks / open issues | 60 / 15 / 1 |
| Default branch | `master` |

Contents: `recompiler/`, `runner/`, `external/` (submodules), `docs/`,
`tests/`, `tools/`, `ghidra/`, `release/`, and three legacy game directories
(`puyo/`, `rka/`, `sonicthehedgehog/`), plus the top-level policy documents
`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `PERMISSIONS.md`, `PRINCIPLES.md`,
`COSIM.md`, `COVERAGE.md`, `DEBUG.md`, `RELEASING.md`,
`GENESIS_AUDIO_FIDELITY.md`, `WIDESCREEN_ISSUES.md`.

Submodules (from `.gitmodules`):

```
external/m68k-recomp-core   ../m68k-recomp-core.git
external/z80-recomp-core    ../z80-recomp-core.git
external/recomp-net         https://github.com/RetroPortingToolKit/recomp-net.git
external/rbengine           https://github.com/RetroPortingToolKit/rbengine.git
sonicthehedgehog/s1disasm   https://github.com/sonicretro/s1disasm.git
```

## Published game projects

Game integrations live in **their own repositories**, named `<Game>Recomp`:

| Game | Repo |
|---|---|
| Sonic the Hedgehog | `mstan/SonicTheHedgehogRecomp` |
| Sonic the Hedgehog 2 | `mstan/SonicTheHedgehog2Recomp` |
| Sonic CD (Sega CD) | `mstan/SonicCDRecomp` |
| Sonic 3 / S&K / S3&K | `mstan/Sonic3AndKnucklesRecomp` |
| Rocket Knight Adventures | `mstan/RocketKnightAdventuresRecomp` |

The framework README describes these as showing adaptive ultrawide, modern
controls, mods, multiplayer, save states and rewind, with different feature
limits per game.

**Issue #17** ("List of games I would like to see in this project") lists 18
wanted titles (Thunder Force III/IV, Gunstar Heroes, Streets of Rage 2, Ristar,
Castlevania: Bloodlines, Comix Zone, Earthworm Jim, ToeJam & Earl, …).
**Shadowrun is not on it**, so a new integration is not duplicating anything
planned.

## Integration requirements (`docs/GETTING_STARTED.md`)

Quoted points that shape our M9 layout:

* "Start with a separate game project … Keep game-specific configuration, source
  and assets in that game's repository, with the framework pinned as a
  submodule. **The legacy game directories inside this framework are migration
  history rather than the layout to copy for new projects.**"
* "Your new `game.toml` must describe your game's ROM identity, discovered
  routines, dispatch and bank/data behavior."
* "Generated C is one part of the port. The consuming game's **CMake and adapter
  must connect it to the runner**, define frame execution, provide ROM checking
  and handle the title's runtime integration."
* "**Keep generated files in ignored output directories**; fix analysis or
  runtime behavior instead of hand-editing emitted functions."
* "Validate the stock game first. Choose one short route: cold boot, title
  selection, first gameplay scene. Compare input, scenery, collision, scrolling,
  audio and transitions against the original game in a trusted emulator.
  Record passed, failed and untested checks. **A title screen is not a campaign
  validation.**"
* Windows toolchain: Visual Studio 2022 + CMake (`recompiler/` as the CMake
  project producing `GenesisRecomp.exe`).

## Pull-request landscape

* Framework repo: 30 PRs returned by the API — **all by mstan** except one:
  * **#49 (open, by `jeremynsl`)** — "Interpreter: match generated code at
    handler RTE and RT…".
* Core repo `mstan/m68k-recomp-core`: **two open external PRs**, both editing
  `profiles/genesis/code_generator.c`, the same file our fixes touch:
  * **#4 (open, by `geno55`)** — "genesis: report SR writes to the runtime for
    exact V-int delivery".
  * **#5 (open, by `jtf323`)** — "genesis: compile `TRAP #n` with a ROM handler
    as a call".
* `mstan/z80-recomp-core`: no PRs yet.

**Conclusion:** external code-generation PRs are precedented and currently open
against the same component. Our two codegen fixes and the SRAM mapping fix are
plausible PRs.

## Contribution terms

From `CONTRIBUTING.md`:

> License each contribution under the terms already applicable to the files
> being changed. For contributions to code covered by the PolyForm Noncommercial
> License, **also grant the additional permissions in `PERMISSIONS.md`** for the
> rights you control in your contribution, and authorize Matthew Stanley to grant
> those same additional permissions for it.

From `PERMISSIONS.md`: the additional permissions cover donations/advertising
and require that the software, games and their content stay **free to access**
(no paid copies, subscriptions, early access or paid content). Our repo therefore
must not be sold or paywalled, and a contribution must carry that grant.

## What this means for us

| Decision | Reason |
|---|---|
| Public repo is `ShadowrunRecomp`, framework as submodule | matches the five published game repos |
| Generated C ignored, regenerated by script | upstream rule |
| We ship no ROM, assets, audio, or real saves | IP + upstream norm |
| `docs/STATUS.md` with passed/failed/untested | upstream validation requirement |
| PRs: 2 to `m68k-recomp-core`, 1 to `segagenesisrecomp` | precedent + one is invited by an in-code comment |
| Our `game.toml` seeds stay in our repo | game-specific, not framework material |
| Offer: GCC/MinGW build recipe, headless runner, audio capture, SRAM tracing | things upstream does not have |
