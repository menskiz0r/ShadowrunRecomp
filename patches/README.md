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

## 0002-rts-return-slot.patch

`profiles/genesis/code_generator.c`. The `rts` emitter consumed `_sp_popped` as
"the return address was already popped" whenever the function had any `(SP)+`
operand. Ordinary saved-register restores (`move.w (a7)+,d0` right before the
`rts`) therefore made the caller skip its return-slot pop - a 4-byte stack leak
per call that grows without bound.

Found with the Tier-3 co-simulation: A7 diverged by 4 bytes at cp 327 and by
0x230 bytes by cp 1200; the divergence began at `$0C88` calling `$0E34`, whose
epilogue is `move.w (a7)+,d0` / `move.w (a7)+,sr` / `rts`.

The patch only lets a callee consume its return slot when it is **proven** to
capture the return (`m68k_return_capture_is_unconditional`, the same predicate
the call sites use) or when it skips SP with an explicit `ADDQ/SUBQ` (the SMPS
stop-track pattern). After it, A7, D1 and RAM match the interpreter at every
checkpoint through 3 M cycles.

## 0003-call-site-return-slots.patch

`profiles/genesis/code_generator.c`. Indirect `jsr`/`bsr` (`jsr (a0)`) sites already
push a return slot and remember its address. After the call they now compare A7
against that slot: a callee that consumed more than its own return (`_tail_k >= 2`)
gets its final `rts` slot put back and that many C frames unwound.

Needed by Shadowrun's check-out confirm (`$DA6A`), reached through the menu
dispatcher `$C436`'s `jsr (a0)`: on Yes it pops the caller's return and the
dispatcher's return, then `rts`s past both. Solved at the call site because every
attempt to classify the capture inside the callee (`rts` rejection, pop width,
A7 delta at the `rts`) either left the menu loop unexited or broke boot.

After it: the route in `scripts/route-user.input` lands in the hotel room exactly
like the interpreter, boot hashes are unchanged (`0x45E5`/`0xE29B`/`0x06B5` at
frames 1000/2000/3000), a 12 000-frame run has no watchdog, FM peak 7395 and PSG
peak 8182.
