/* shadowrun_compat.h - force-included declarations for the generated C.
 *
 * Current m68k-recomp-core emits glue_sr_written() for SR-writing instructions
 * (upstream PR #4), but the segagenesisrecomp runner pinned here (v0.1.2) does
 * not declare or define it. The generated translation units therefore need a
 * prototype, and the spec provides the no-op definition. Remove both once the
 * runner consumes the hook.
 */
#ifndef SHADOWRUN_COMPAT_H
#define SHADOWRUN_COMPAT_H

void glue_sr_written(void);

#endif
