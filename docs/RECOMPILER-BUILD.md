# Recompiler build + first patch

`GenesisRecomp` is now buildable from source in this tree, which makes code-generation
fixes possible instead of being limited to the shipped binary.

## Build

```
# the recompiler's src/*.c forwarding stubs expect the core at:
#   segagenesisrecomp-master/external/m68k-recomp-core/{common,profiles}
# populated from the m68k-recomp-core checkout

pwsh port/build_recompiler.ps1      # -> port/build/GenesisRecomp_fixed.exe
```

Sources: `recompiler/src/{main_genesis,rom_parser,game_config,toml}.c` plus
`m68k-recomp-core/{common,profiles/genesis}/*.c`.

## Patch 1 — MOVEM frame restores are not skipped returns

`profiles/genesis/code_generator.c`, MOVEM `(A7)+` emitter:

```c
/* before */
if (dir == 1 && mode == 3)
    fprintf(f, "  _sp_popped += %d; /* MOVEM (SP)+ bytes */\n", ...);

/* after */
if (dir == 1 && mode == 3)
    fprintf(f, "  /* MOVEM (SP)+ frame restore: not a skipped return */\n");
```

**Why:** `_sp_popped` feeds the `rts` emitter's "skip N caller returns" count. A `movem`
restore belongs to the function's own saved frame and never discards a return slot. Counting
it made shared-epilogue code (prologue in one function, `movem`+`unlk`+`rts` in another) look
like a multi-slot skip.

This removes one false positive but does **not** yet fix the Shadowrun boot leak — see
`MILESTONE4.md`, the `$052F00 -> $052EB0` site still loses 18 bytes because the
captured-return/shared-epilogue chain (`$052E4E` prologue, `$052E84` epilogue, `jmp` between
them) is not modelled as one frame.

## Next

Model the shared-epilogue idiom explicitly: a `jmp` into a block that pops `sr`/`movem`/`unlk`
and `rts` belongs to a frame opened by a *different* entry point, so the epilogue must not be
treated as an independent function with its own return bookkeeping.
