# Command Reference

This file is generated from live CLI help output.

Authoritative help:

```sh
relato --help
```

To regenerate:

```sh
make generate-command-docs
```

## Commands

- `relato version`
- `relato store summary [--db PATH]`
- `relato store list [--limit N] [--db PATH]`
- `relato store uploads [--limit N] [--db PATH]`
- `relato categories [--db PATH]`
- `relato categorize --title TEXT [--description TEXT] [--bundle-id ID]`
- `relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--kind bug|suggestion] [--output-dir DIR]`
- `relato routes`
- `relato open ROUTE [--id ID] [--print-only]`
- `relato open-native [--payload PATH]`
- `relato fill [--payload PATH] [--select-popups] [--script PATH]`
- `relato submit [--payload PATH] [--select-popups] [--script PATH] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]`

## Scripting Tips

- Use `relato submit --dry-run` before `--confirm` to preview the native handoff plan.
- Use `relato open ROUTE --print-only` when you only need the Feedback Assistant URL.
- Use `relato store summary` and `relato store list` for local verification after native submission.
- Treat local store verification as local evidence, not an Apple server receipt.
