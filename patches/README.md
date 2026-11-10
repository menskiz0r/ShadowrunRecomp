# Framework patches

The framework is consumed as a submodule and is **not** forked here. This folder
holds the smallest set of fixes this game needs on top of it, applied by
`scripts/apply-framework-patches.ps1`.

## 0001-return-capture.patch — still required

**Target:** `segagenesisrecomp/external/m68k-recomp-core`

`return_capture.c` treats a routine that pops the caller's return address as
"capture and take over" even when it immediately rebuilds a frame and returns
normally. Shadowrun's Z80-bus helper at `$052E4E` does exactly that, so its six
callers (`$052EB0`, `$052EC6`, `$052F3C`, `$052F5A`, `$052F6E`, `$052FA0`) were
emitted as `push return; call; return;` with their bodies dropped, leaking the
pushed slot (18 bytes per call).

Checked against `m68k-recomp-core` `main` on 2026-11-09: still unfixed
(`result = true` in `prove_from`). Reported as
<https://github.com/mstan/m68k-recomp-core/issues/14> and submitted as
<https://github.com/mstan/m68k-recomp-core/pull/15> (one file, +42/-1, built and
tested against this port). Drop this patch when that merges.

## No SRAM patch needed — pin the framework correctly

Shadowrun needs always-mapped SRAM (16 KB at `$200000`, 2 MB ROM, cart never
writes `$A130F1`). **Upstream already implements this**: commit `a7e8c5ea`
"Support always-mapped cartridge SRAM" (2026-10-24), auto-detected in
`gbus_sram_setup()`, with a test.

* Framework at `a7e8c5e` or later → nothing to patch.
* Framework at **v0.1.2** (2026-10-23) or earlier → SRAM access is dropped and
  the game reports "Game Saved!" without writing anything; pin forward.

I originally filed <https://github.com/mstan/segagenesisrecomp/issues/71> for
this and corrected it in the thread once I checked `master`.

## Applying

```powershell
powershell -ExecutionPolicy Bypass -File scripts\apply-framework-patches.ps1
```

The script applies each patch with `--dry-run` first, then for real, and stops on
the first failure. Re-running is safe: an already-applied patch is reported as
such and skipped.
