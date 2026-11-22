# Shadowrun (Sega Genesis) - Weapons

Short reference for the weapons in the current build. Damage is the in-game
damage rating, not a real-world value. Prices are in nuyen.

## Firearms

| Weapon | Type | Clip | Damage | Price |
| --- | --- | --- | --- | --- |
| Streetline Special | Light pistol | 6 | 4 | 100 |
| Model 101T | Light pistol | 12 | 6 | 350 |
| American L36 | Light pistol | 11 | 6 | 300 |
| Security 500 | Light pistol | 25 | 6 | 450 |
| Warhawk | Heavy pistol | 6 | 10 | 500 |
| Max-Power | Heavy pistol | 10 | 9 | 450 |
| Predator | Heavy pistol | 15 | 9 | 450 |
| AK-97 SMG | SMG | 30 | 6 | 1,000 |
| HK227-S SMG | SMG | 28 | 7 | 1,500 |
| Mach 22 SMG | SMG | 24 | 6 | 800 |
| Allegiance Shotgun | Shotgun | 5 | 10 | 1,400 |
| Roomsweeper Shotgun | Shotgun | 8 | 9 | 1,000 |

Notes:

- Light pistols are cheap and easy to conceal.
- Heavy pistols trade clip size for damage.
- SMGs offer large clips and automatic fire.
- Shotguns have small clips and high damage.

## Grenades

| Weapon | Role |
| --- | --- |
| Frag Grenade | Anti-personnel fragmentation explosive |
| Scatter Grenade | Wide-area shrapnel explosive |
| Concussion Grenade | Concussion/stun explosive |

Grenades are thrown weapons and use the Throwing skill. They occupy inventory
slots and are consumed when used.

## Melee and cyberweapons

| Weapon | Type | Notes |
| --- | --- | --- |
| Unarmed | Natural | Uses Strength and Melee Combat |
| Hand Razors | Cyberware | Implanted melee weapon; installed at a clinic |
| Spurs | Cyberware | Implanted melee weapon; installed at a clinic |
| Enchanted Dagger | Cut item | Price 50,000; damage 0; no shop sells it. Unused/cut content |

Melee attacks use the Melee Combat skill and are affected by Strength and
cyberware.

## Weapon accessories

Accessories are attached to guns through the inventory item modifiers.

| Accessory | Effect |
| --- | --- |
| Smartlink | Improves accuracy when paired with smartlink cyberware or smart goggles |
| Silencer | Suppresses the sound of a shot |
| Sound Suppressor | Further sound suppression |
| Laser Sight | Improves aiming |
| Gas Vent II | Reduces recoil |
| Gas Vent III | Stronger recoil reduction |
| Smart Goggles | External smartlink support |

## Ammunition

- Each gun uses a clip and has a maximum clip size.
- Reloading and trading clips are handled from the Clips menu.
- Ammo is tracked per weapon; a weapon with an empty clip must be reloaded.

## Armor

Armor is not a weapon, but it affects combat survivability.

| Armor | Notes |
| --- | --- |
| Armor Vest | Light armor |
| Armor Clothing | Light concealable armor |
| Armor Jacket | Medium armor |
| Vest With Plates | Medium armor |
| Lined Duster | Medium/heavy armor |
| Light Combat Armor | Heavy armor |
| Heavy Combat Armor | Heaviest armor |

## Magic weapons and foci

These are not conventional weapons:

| Item | Purpose |
| --- | --- |
| Power Focus | Improves spell success |
| Spell Focus | Reduces drain for a specific spell |
| Protection Talisman | Improves magic defense |
| Combat Sense Spell Lock | Improves combat defense |
| Rat Totem | Shaman totem |
| Gator Totem | Shaman totem; starting item for the Shaman class |
| Bear Totem | Shaman totem |

The Mage class starts with a Power Focus. The Shaman starts with the Gator
Totem. Shaman spell-focus items are removed from the Mage at runtime.

## Current mod notes

- The current ROM does not change weapon stats or prices.
- The four-class change gives the Mage a Power Focus instead of the Gator
  Totem.
- Shaman spell foci are filtered from the Mage's inventory; weapon items are
  unaffected.

## Source

The firearm statistics above come from the game's item/weapon table at
`0x0D4510`. The current patched ROM keeps the original weapon data.
