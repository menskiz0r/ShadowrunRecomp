# Shadowrun (Sega Genesis) - Characters

A short roster of the named characters in the current build. The player
character is always **Joshua**; the class chosen at creation sets the
archetype, starting gear, portrait, and magic rules.

## Playable character

| Name | Role | Notes |
| --- | --- | --- |
| Joshua | Player character | Human shadowrunner investigating the death of his brother Michael |

## Playable classes

| Class | Archetype | Summary |
| --- | --- | --- |
| Samurai | `2` | Combat-focused. Original template. |
| Decker | `3` | Matrix-focused. Original template. |
| Shaman | `1` | Magic user. Original Gator Shaman template; Gator Totem; shaman spells allowed. |
| Mage | `0` | Custom fourth class. Power Focus; Trent portrait; starts with Mana Zap level 4; shaman spells and shaman spell-focus items are blocked. |

Mage and Shaman share the same base attributes and skills. Their main
differences are the archetype byte, starting item, portrait, and spell-school
restriction.

## Hireable runners

All ten runners use the game's 256-byte runner templates. The location is the
place where they can be found or hired.

| Runner | Race / Role | Location | Notes |
| --- | --- | --- | --- |
| Ricky | Dwarf Rat Shaman | Jackal's Lantern, Redmond Barrens | Template overwritten by the Mage class in the current ROM |
| Winston Marrs | Troll Samurai | Big Rhino, Penumbra District | Heavy combat runner |
| Trent | Human Mage | Space Needle Bar, Downtown Seattle | His portrait is used for the player Mage |
| Petr Uvehr | Dwarf Decker | The Wanderer, Puyallup Barrens | Matrix specialist |
| Walking Bear | Ork Bear Shaman | Friendship Restaurant, Council Island | Shaman and story contact |
| Phantom | Elf Decker | The Frag Grenade, Renraku Arcology | Matrix specialist |
| Ilene Two Fists | Human Samurai | Jump House, Redmond Barrens | Melee/combat runner |
| Freya Goldenhair | Elf Mage | Club Penumbra, Penumbra District | Mage |
| Rianna | Elf Decker | The Matchstick, Downtown Seattle | Decker |
| Stark | Human Samurai | Underground 93, Puyallup Barrens | Michael's surviving friend; helps investigate the ambush |

**Current build note:** the fourth class template occupies the record that
originally held Ricky. Ricky's original runner data is therefore replaced by
the Mage class template. The other nine runners are unchanged.

## Story characters

| Name | Role | Summary |
| --- | --- | --- |
| Michael | Joshua's brother | Deceased shadowrunner; his death drives the story |
| Stark | Michael's friend | Surviving member of Michael's team; hireable ally |
| Harlequin | Elf fixer / quest giver | Mysterious powerful figure tied to the late-game story |
| Thon | Final antagonist | The final boss of the campaign |
| Chief Running Stream | Shaman leader | Leads the Medicine Lodge community on Council Island |
| Spirit Eyes | Powerful shaman | Medicine Lodge quest contact; requires spell components |
| Walking Bear | Ork Bear Shaman | Medicine Lodge / Council Island contact and runner |

## Fixers, shopkeepers, and service contacts

| Name | Role | Services / information |
| --- | --- | --- |
| Roscoe | Fixer | Buys data files and provides runner work |
| Riannon Heartbane | Shaman / shopkeeper | Runs Riannon's Magic Shop in Puyallup Barrens |
| Merlin | Mage / shopkeeper | Runs Merlin's Lore in the Renraku Arcology |
| Dr. Bob | Doctor / shopkeeper | Runs Dr. Bob's Quickstitch in Puyallup Barrens |
| Capt. Quinton Jaymes | Ex-merc | Hollywood information; sells frag grenades and stripped HK227-S; offers a rigger contact |
| Alesandro Hobbs | Company man | Paranormal creature information; sells maglock passkeys; offers a Hollywood contact |
| Sharkey | Rigger | Passage to Salish-Shidhe and Sinsearach; sells smart goggles |
| Kipp David | Corporate decker | Corporate Matrix information; sells high-level programs and the Excalibur cyberdeck |
| Wilma Temmenhoff | Street decker | Matrix information; sells programs |
| Sergeant Macklemann | Hollywood security guard | Corporate security information; offers Hollywood access |
| Gregory Wilns, PhD | Corporate mage | Corporate security information; offers a Power Focus and a Merlin's Lore discount |
| Mr. Faradouchi | Mafia Don | Free stay at Wylie's Gala Inn; Crime Mall discount; keeps Lone Star away |
| Agira Tetsumi | Yakuza boss | Little Chiba discount; heavy combat armor; Power Focus |
| Henry J. Culver | Seattle city official | Deletes Lone Star records; Hollywood access; weapon permit |
| Max | Fixer | Sells corporate badges, weapons, and maglock passkeys |
| Sgt. Chillicut | Lone Star detective | Deletes Lone Star records; Hollywood access; weapon permit |
| Professor Jefferson | University mage | Paranormal creature information; Riannon's discount; corporate mage contact |

## Mr. Johnson mission contacts

Random mission briefings are given by:

- Mr. Gunderson
- Julius Strouther
- Mortimer Reed
- Vigore and Jarl
- Caleb Brightmore

## Factions and antagonists

| Faction / group | Role |
| --- | --- |
| Lone Star | Seattle police and security force |
| Ares | Megacorporation and weapons manufacturer |
| Aztechnology | Megacorporation |
| Fuchi | Megacorporation and Matrix technology |
| Mitsuhama | Megacorporation |
| Renraku | Megacorporation and Arcology owner |
| Halloweeners | Human gang in Redmond Barrens |
| Eye-Fivers | Elf gang in Penumbra District |
| Orks | Ork gang in Puyallup Barrens |
| Thon | Final boss |

Corporate security, corporate mages, hell hounds, gargoyles, wendigos, and
other paranormal creatures are common combat enemies.

## Current mod status

- The ROM is the **1995 Four Classes** build.
- Playable order: Samurai, Decker, Shaman, Mage.
- The Shaman is the original Gator Shaman: archetype `1`, Gator Totem, shaman
  spellbook allowed.
- The Mage is archetype `0`: Power Focus, Trent's Human Mage portrait, Mana Zap
  level 4, and no shaman spells or shaman spell-focus items.
- Shop menus are not patched; the Mage restriction is applied at runtime to the
  spellbook and focus inventory.
- Ricky's hire template is overwritten by the Mage template. If Ricky is
  expected in the hiring roster, he will not appear with his original data.
