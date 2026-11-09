# Contributing

## Licensing

License each contribution under the terms already applicable to the files being
changed. For contributions to code covered by the
[PolyForm Noncommercial License](LICENSE.md), also grant the
[additional permissions in `PERMISSIONS.md`](PERMISSIONS.md) for the rights you
control in your contribution, and authorize Matthew Stanley to grant those same
additional permissions for it (the framework lives under the same terms).

These terms do not replace the licenses of third-party code or project
components expressly licensed under other terms. Do not contribute material you
lack permission to license, or copy from incompatible or proprietary sources.

## No game content

Never commit or attach a ROM, extracted graphics, audio, save files or
screenshots of game content. See [`RELEASING.md`](RELEASING.md).

## Before you send a change

```powershell
powershell -ExecutionPolicy Bypass -File scripts\validate-all.ps1
```

The validation report in `docs/VALIDATION-REPORT.md` records what is expected to
pass; a change that flips one of those results needs the report updated in the
same commit.
