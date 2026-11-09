# Milestone 7 — saves ✅

Battery SRAM is mapped, persisted, and the game's own save/load works across
restarts.

| Step | Screen |
|---|---|
| Save/Load Game | *save/load* (screenshot not distributed: copyrighted game imagery) |
| Game saved | *saved* (screenshot not distributed: copyrighted game imagery) |
| Load Game | *load* (screenshot not distributed: copyrighted game imagery) |
| Loaded | *success* (screenshot not distributed: copyrighted game imagery) |

## The bug that blocked it

The ROM never touches `$A130F1` (verified: zero occurrences), because its SRAM
window at `$200000` lies **past the end of the 2 MB ROM** and therefore never
shadows it. Such cartridges expect SRAM to be **always mapped**.

The framework's bus gates SRAM on the `$A130F1` overlay bit, so every access was
dropped — `g_sram_reads`/`g_sram_writes` stayed at 0 for the whole session, which
is what made the save silently do nothing.

Fix (adapter): after `gbus_sram_setup()`, enable the overlay permanently when the
window does not overlap the ROM image:

```c
if (g_machine.bus.sram_present && g_machine.bus.sram_base >= rom_size) {
    g_machine.bus.sram_enabled = 1;   /* window does not shadow ROM */
}
```

## Verified end to end

```
SRAM: present (16384 bytes at $200000)
SRAM: window does not shadow ROM -> always mapped
SRAM: loaded 16384 bytes from saved.srm
SRAM: saved 16384 bytes (checksum 1E50BB9A) to saved.srm
```

* Saving writes **1558 bytes**; the slot name is visible in the raw data
  (`00 20 00 47 00 41 00 4D 00 45` = " GAME ").
* Restarting with that `.srm` shows both slots populated; selecting Game 1 loads
  and the game answers **"Successful download! Press any button to run in the
  shadows."**

## Also fixed on the way here

* The Pocket Secretary's node table at `$C1400` — all six entries were
  untranslated interior labels (`$00F236`, `$00C8C8`, `$018150`, `$00C448`,
  `$00EFB4`, `$0599DA`).
* The status panel's mode dispatch at `$11740` → table `$D2A0A` — nine more
  interior targets (`$011B58` … `$011040`).

Together with the earlier seeds that is 951 translated functions.

## Reproduce

```
DSH_SRAM=shadowrun.srm shadowrun_runner.exe "Shadowrun (U) [!].bin" 24000
```

with the menu script in `MILESTONE5.md` (Start → 7×Right → A → 4×Down → A →
A → A to save; Down → A → A → A to load).
