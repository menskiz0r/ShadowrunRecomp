/*
 * shadowrun_spec.c - GameSpec for Shadowrun (Sega Genesis, 1994), USA NTSC.
 *
 * ROM layout: flat 2 MB at $000000-$1FFFFF, identity-mapped, 16 KB battery SRAM
 * declared in the header at $200000-$203FFF. Because that window lies beyond the
 * ROM image it can never shadow ROM, so the cart does not use the $A130F1
 * overlay bit at all (the ROM contains zero references to it). This runtime
 * needs `gbus_sram_set_always_mapped()` for those saves to persist - see
 * CHANGELOG / upstream issue mstan/segagenesisrecomp#71.
 *
 * Boot/dispatch, taken from the 68K vector table at $000000:
 *   reset PC          = $000236   (entry; SSP comes from the header, $00FFFFF8)
 *   VBlank (IRQ6)     = $00022E
 *   HBlank (IRQ4)     = $000228
 * The game installs further handlers in RAM later; those go through the
 * generated dispatch table, not this struct.
 */
#include "game_spec.h"
#include "genesis_runtime.h"
#include "glue.h"

#include <stddef.h>
#include <stdint.h>

/*
 * Weak linkage: newer framework revisions provide these host hooks themselves
 * (see patches/README.md), older ones do not. Declaring our copies weak means a
 * strong framework definition wins and a missing one falls back to us.
 */
#if defined(__GNUC__) || defined(__clang__)
#define SHADOWRUN_WEAK __attribute__((weak))
#else
#define SHADOWRUN_WEAK
#endif

/*
 * Compatibility shim.
 *
 * Current m68k-recomp-core emits glue_sr_written() after an instruction that
 * writes SR (upstream PR #4, "report SR writes to the runtime"), but the
 * segagenesisrecomp runner this project pins (v0.1.2) does not define it. The
 * validated port was built against a core from before that change, so a no-op
 * here preserves the exact behaviour the milestone evidence was gathered on.
 * Drop this shim once the runner consumes the hook.
 */
SHADOWRUN_WEAK void glue_sr_written(void) {}

/*
 * STOP #imm: park the guest until the next interrupt (frame boundary).
 * genesis_runtime.h declares this as game-owned, so every host must provide it;
 * the headless adapter and this runner share the same implementation.
 */
SHADOWRUN_WEAK void genesis_stop_until_interrupt(uint16_t sr_imm)
{
    extern M68KState g_cpu;
    g_cpu.SR = sr_imm;
    /* STOP halts the 68K until an interrupt of higher priority arrives. The
     * runtime parks the game fiber so the runner keeps pacing frames and the
     * next VBlank raises the IRQ (see genesis_runtime.h). glue_wait_vblank_done()
     * is a no-op on the fiber runner, so calling it made STOP fall through. */
    glue_yield_for_vblank();
}

/* ---- Entry-point / interrupt dispatchers (canonical org-0 addresses) ---- */
static void shadowrun_call_entry_point(void) { recomp_call_addr(0x000236u); }
static void shadowrun_call_vblank(void)      { recomp_call_addr(0x00022Eu); }
static void shadowrun_call_hblank(void)      { recomp_call_addr(0x000228u); }

const GameSpec g_game_spec = {
    .video                  = NULL,   /* native VDP presentation only */
    .logical_players        = 1,

    .display_name           = "Shadowrun",
    .short_name             = "Shadowrun",

    /* Shadowrun (USA), 2 MB. Regional variants have different code and data
     * layouts and cannot share this recomp. */
    .expected_rom_crc32     = 0xFBB92909u,
    .expected_rom_size      = 0x200000u,

    /* Every computed-dispatch miss must be loud, not silently interpreted: the
     * validated route reaches no floor fallback, so a miss here is a regression.
     * (GENESIS_FLOOR still overrides when a new route is being explored.) */
    .tier3_floor_default    = 0,

    /* SRAM comes from the header ("RA" at $1B0, $200000-$203FFF); no override
     * needed. The always-mapped quirk is handled in the bus, not here. */
    .sram_start             = 0,
    .sram_end               = 0,

    .call_entry_point       = shadowrun_call_entry_point,
    .call_vblank            = shadowrun_call_vblank,
    .call_hblank            = shadowrun_call_hblank,
};
