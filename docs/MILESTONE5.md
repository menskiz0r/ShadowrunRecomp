# Milestone 5 — first room playable ✅

The game is playable end-to-end: title → menu → archetype → opening narrative →
hotel room → character sheet → check out → **walking around the room**, with the
HUD live and the map scrolling.

| Step | Screen |
|---|---|
| Title / menu | *menu* (screenshot not distributed: copyrighted game imagery) |
| Archetype select | *archetype* (screenshot not distributed: copyrighted game imagery) |
| Opening narrative | *text* (screenshot not distributed: copyrighted game imagery) |
| Character sheet (Karma) | *sheet* (screenshot not distributed: copyrighted game imagery) |
| Check-out confirmation | *checkout* (screenshot not distributed: copyrighted game imagery) |
| **In the room** | *room* (screenshot not distributed: copyrighted game imagery) |
| **Walking** | *walk* (screenshot not distributed: copyrighted game imagery) |

## The bug that finished it

The hotel terminal's menu is driven by a jump table, and **both of its action
routines were interior labels the recompiler never translated**:

```
0C14C8: 0000D024   ; node[0] -> Karma Screen        (interior: untranslated)
0C14CC: 0000DA6A   ; node[1] -> Check Out           (interior: untranslated)
0C14D1: " Hotel Options ... Karma Screen ... Check Out"
```

The runner is four instructions:

```
00C436  move.b  $FFF0DC,d0     ; selection index
00C43E  lsl.w   #2,d0
00C440  movea.l (a0,d0.w),a0   ; node[selection]
00C444  jsr     (a0)           ; -> called an address with no generated function
```

Seeding `0x00D024` and `0x00DA6A` in `game.toml` `[functions].extra` made both
actions real functions (translation 782 → 789). After that the whole interface
works:

* **A** on "Karma Screen" opens the character sheet (Joshua, Human Samurai —
  attributes, skills, karma).
* **Start** closes it and returns to the hotel menu.
* **Down + A** on "Check Out" opens "Do you wish to check out? Yes / No".
* **Up + A**, then **A**, confirms — and the character steps out into the room.

## Verified

* The character sprite moves with the D-pad; the map scrolls to follow.
* Walking right/down/left/up for thousands of frames stays stable
  (~32.7 M instructions by frame 24,000, no watchdog, no crash).
* 28 colours on screen, HUD (portrait, health, karma, items) live throughout.

## Reproduce

```
DSH_PRESSES="2100:S,3300:A,5000:B,7000:A,7300:A,7600:A,7900:A,8200:A,8500:A,\
8800:A,9100:A,9400:A,9700:A,12000:S,12400:DA,14600:UA,15100:A,\
17000:R,17600:R,18200:R,18800:R"
shadowrun_runner.exe "Shadowrun (U) [!].bin" 19600 shot.bmp
```

`frame:buttons`, 6-frame pulses, released every frame. `DA` = Down+A on the same
frame (the selection index `$FFF0DC` is cleared each iteration, so the direction
and confirm must land together).
