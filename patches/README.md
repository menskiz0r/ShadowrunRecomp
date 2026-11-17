# Patches

## Upstream status (2026-11-17)

The port now pins `m68k-recomp-core` at **`ddae973` = `v0.1.1`**, which is upstream
`main` and contains the three PRs this port produced, reworked by the maintainer:

- PR #15 "prove return capture across every reachable exit" -> integrated as
  `dfda0b3`/reviewed variants, plus follow-ups
- PR #18 "rts may only consume a return slot it was proven to capture"
- PR #19 "indirect calls unwind the return slots the callee consumed"

All three landed in one merge commit and are released as `v0.1.1`. The maintainer
reworked the capture proof (`return_capture.c` grew a reviewed implementation) and
added six follow-up commits of his own. Our approach survived (`_tail_k >= 2` call-site
unwinding, `function_finder_pops_return_unconditionally`, `s_func_explicit_sp_skip`).

**Patches 0001-0003 are therefore retired** (moved to `retired-upstream/`); do not apply
them on top of `ddae973`. Verified after the update: boot hashes unchanged
(45E5/E29B/06B5/29F9/5F8D/11C1), combat replay matches all 5042 inputs with an empty
interior-label miss list, sound behaviour unchanged (FM thirds 6570/383/383).

## Active patches

- `0004-local-debug-tooling.patch` - runner diagnostics (session capture, watchpoints,
  replay switches, chunk log, VDP counter, audio dump). No emulation behaviour change
  unless the matching env var is set.
- `0005-instruction-trace.patch` - per-instruction `GEN_TRACE(pc, cycles)` emission in
  the recompiler, addressing every instruction site (used to compare the two backends).

