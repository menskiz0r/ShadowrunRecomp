# ROM patch: four classes

The `port/four-classes` branch builds against a patched USA cartridge image.
The stock dump is not enough: `game/shadowrun_spec.c` pins the patched CRC32, so
the runner refuses an unpatched image.

## Image identity

| | Bytes | CRC32 | SHA-1 |
| --- | --- | --- | --- |
| Original USA dump | 2 097 152 | `FBB92909` | `A06A281D39E845BFF446A541B2FF48E1D93143C2` |
| Four-class image | 2 097 152 | `93B0D845` | `2F0FFB4C402972A183C936C17A10E9941123AC07` |

## Patch file

```
patches/rom/Shadowrun (USA) 1995 Four Classes.ips
```

| Property | Value |
| --- | --- |
| Format | standard IPS (`PATCH` ... `EOF`) |
| Size | 184 bytes |
| SHA-256 | `4033D9907470D06972A778277C99329D2DA845C32A3428924EE010E8CB6843C4` |
| Changed bytes | 60, in 30 runs, packed into 10 records |
| Base size | 2 097 152 bytes, unchanged by the patch |

Apply it with any IPS patcher (flips, Lunar IPS, RomPatcher.js, or the patch
function of most front-ends). The patch only rewrites existing bytes, so the
result stays at 2 MB and the `.gen` extension remains valid.

Or let the repository do it, hash-checked at both ends:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\apply-rom-patch.ps1 -Rom "D:\roms\Shadowrun (USA).gen"
```

The helper reads the stock dump (CRC32 `FBB92909`), applies the records above,
rejects any other input image, and writes `game/shadowrun.bin`, so the manual
copy step disappears. `-Out` changes the destination and `-Patch` an alternative
IPS file.

Verification after patching:

- CRC32 is `93B0D845`
- SHA-1 is `2F0FFB4C402972A183C936C17A10E9941123AC07`
- the header checksum word at `0x18E` is `0xBE5C` (was `0x6BAF`)

## Net changes relative to the original dump

| Offset | Old | New | Meaning |
| --- | --- | --- | --- |
| `0x00011B` | `34` | `35` | header copyright 1994 -> 1995 |
| `0x00018E` | `6B AF` | `BE 5C` | header checksum recomputed |
| `0x001F7A` | `34` | `35` | title-screen copyright 1994 -> 1995 |
| `0x0592A3` | `02` | `03` | `MOVEQ #2,D3` -> `MOVEQ #3,D3`, four menu entries |
| `0x072C1A`..`0x072C1F` | `06 40 00 00 06 40` | `07 80 00 00 07 80` | fourth template header fields |
| `0x072C29`..`0x072C2A` | `0B 0D` | `03 0F` | fourth template fields |
| `0x072C35`..`0x072C40` | `01 .. 19 .. 03` | `00 .. 01 .. 00` | archetype `0x00` (Mage), starting item `0x18` (Power Focus) |
| `0x072C59`..`0x072CA6` | `FF C3 40 .. "Ricky " .. 07 22 DA` | `FF BF 40 .. "Joshua " .. 07 24 1A` | portrait pointers, name field, rest of the Mage template |
| `0x072CB4`..`0x072CBB` | `02 01 .. 00` | `00 00 .. 04` | template stats and skill tail |
| `0x1B6507`..`0x1B6515` | `"Gator\x80    Shama"` | `"Shaman\x80\x80  Mage\xFF"` | archetype menu rebuilt |

Two items in the port's change log are net no-ops: class template 2 at
`0x72B1A` and the character-info archetype entry at `0xD19ED` already match the
original bytes, so the patch does not touch them.

## Classes

| Index | Class | Archetype | Template | Notes |
| --- | --- | --- | --- | --- |
| 0 | Samurai | `2` | original | no magic |
| 1 | Decker | `3` | original | no magic |
| 2 | Shaman | `1` | original Gator Shaman | Gator Totem `0x2A`, shaman spells allowed |
| 3 | Mage | `0` | Ricky's record, rewritten | Power Focus `0x18`, Trent portrait `0x0007241A`, Mana Zap level 4 |

The fourth template occupies the record that originally held Ricky, one of the
hireable runners, so his template is overwritten by the Mage class.

## Mage spell filtering

The filter is host-side, in `game/shadowrun_spec.c`
(`shadowrun_apply_mage_start`), not in the ROM patch. It runs on every VBlank
and acts only when the current character's archetype byte is `0x00`:

- shaman spells `00`-`05`, `0C`, `0D` are dropped from the spellbook;
- shaman focus items `19`-`1E`, `25`, `26` are cleared from the inventory;
- if no spell remains, Mana Zap level 4 (`07 04`) is granted.

Blocked shaman spell IDs: `00` Flame Dart, `01` Flame Bolt, `02` Hellblast,
`03` Invisibility, `04` Sleep, `05` Stink, `0C` Confusion, `0D` Barrier.

Blocked shaman focus items: `19` Flame Dart SF, `1A` Flame Bolt SF,
`1B` Hellblast SF, `1C` Invisibility SF, `1D` Sleep SF, `1E` Stink SF,
`25` Confusion SF, `26` Barrier SF.

## Menu string note

The rebuilt menu string is two bytes shorter than the original. The leftover
`6E FF` after its terminator is unreachable because the menu list terminates at
the first `FF`, and the following entries keep their own offsets.

## Legal note

The IPS patch carries ROM-derived bytes. It is included here so the branch is
reproducible, and it is covered by the same rules as the ROM: keep it local, do
not redistribute it, and remove it on request. See [../README.md](../README.md)
for the full legal posture.
