# Command Reference

This file is generated from live CLI help output. RelatoKit is optimized for agent-driven Feedback Assistant workflows.

## Agent Flow

1. Research the issue and write supporting evidence to a local file.
2. Run `relato prepare` to create `feedback-submission.json` and `feedback-submission.md`.
3. Inspect both files before touching the native app.
4. Run `relato submit --dry-run --payload feedback-submission.json`.
5. Run `relato submit --payload feedback-submission.json` to open and fill only.
6. Inspect Feedback Assistant for native-only fields, diagnostics, and staged attachments.
7. Use `--confirm` only after explicit user confirmation.
8. Use `relato store list` and `relato store uploads` as local evidence afterward.

## Payload Contract

- `feedback-submission.json` is the machine-readable contract used by `open-native`, `fill`, and `submit`.
- `feedback-submission.md` is the human-readable review artifact for logs, notes, or attachments.
- `--snapshot PATH` can point to any local evidence file, not only an image.

## Global Help

```sh
relato: agent-first tooling for Apple Feedback Assistant workflows

RelatoKit is designed for coding agents preparing useful Feedback Assistant
reports through Apple's native macOS app. It keeps authentication, diagnostics,
and final submission inside Feedback Assistant.

Agent workflow:
  1. Research the issue and write any supporting evidence to a local file.
  2. Run `relato prepare` to create the payload pair:
       feedback-submission.json  machine-readable contract for relato
       feedback-submission.md    human-readable report for review/logs
  3. Inspect the Markdown and JSON before touching the native app.
  4. Run `relato submit --dry-run --payload feedback-submission.json`.
  5. Run `relato submit --payload feedback-submission.json` to open/fill only.
  6. Inspect Feedback Assistant for native-only fields, diagnostics, and files.
  7. Only after explicit user confirmation, run with `--confirm`.
  8. Use `relato store list` and `relato store uploads` as local evidence.

Commands:
  relato version
  relato store summary [--db PATH]
  relato store list [--limit N] [--db PATH]
  relato store uploads [--limit N] [--db PATH]
  relato categories [--db PATH]
  relato categorize --title TEXT [--description TEXT] [--bundle-id ID]
  relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--kind bug|suggestion] [--output-dir DIR]
  relato routes
  relato open ROUTE [--id ID] [--print-only]
  relato open-native [--payload PATH]
  relato fill [--payload PATH] [--select-popups]
  relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]

Help topics:
  relato help payload
  relato help prepare
  relato help submit
  relato help fill
  relato help store

Safety:
  `--confirm` clicks the visible native Submit button. It is not headless
  submission and local store verification is not an Apple server receipt.
  Native form automation uses an Objective-C Accessibility/CoreGraphics engine
  with action-first AX and process-targeted CoreGraphics/SkyLight delivery.
  Snapshot attachments are staged into the local Feedback Assistant draft
  folder in the background after the native draft exists.
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
- `relato fill [--payload PATH] [--select-popups]`
- `relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]`

## Topic Help

### `relato help payload`

```sh
relato prepare: create the payload pair agents should review and reuse

Usage:
  relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--kind bug|suggestion] [--output-dir DIR]

Outputs:
  feedback-submission.json
    Machine-readable payload consumed by `open-native`, `fill`, and `submit`.
    Keep this file as the source of truth for the native handoff.

  feedback-submission.md
    Human-readable review artifact. Use it in agent logs, PR notes, or as an
    attachment when useful.

Options:
  --title TEXT          Feedback title.
  --description TEXT    Full report body. Preserve real newlines.
  --snapshot PATH       Local evidence attachment. This can be a screenshot,
                        Markdown note, log, sysdiagnose pointer, or sample file.
  --bundle-id ID        App bundle ID when relevant.
  --kind VALUE          bug or suggestion. Defaults to bug.
  --output-dir DIR      Where to write the JSON and Markdown files.

Agent pattern:
  relato prepare \
    --title "Foundation Models framework: add first-class video input support" \
    --description "$REPORT_BODY" \
    --snapshot ./evidence.md \
    --kind suggestion \
    --output-dir /tmp/relato-report

  sed -n '1,220p' /tmp/relato-report/feedback-submission.md
  relato submit --payload /tmp/relato-report/feedback-submission.json --dry-run
```

### `relato help prepare`

```sh
relato prepare: create the payload pair agents should review and reuse

Usage:
  relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--kind bug|suggestion] [--output-dir DIR]

Outputs:
  feedback-submission.json
    Machine-readable payload consumed by `open-native`, `fill`, and `submit`.
    Keep this file as the source of truth for the native handoff.

  feedback-submission.md
    Human-readable review artifact. Use it in agent logs, PR notes, or as an
    attachment when useful.

Options:
  --title TEXT          Feedback title.
  --description TEXT    Full report body. Preserve real newlines.
  --snapshot PATH       Local evidence attachment. This can be a screenshot,
                        Markdown note, log, sysdiagnose pointer, or sample file.
  --bundle-id ID        App bundle ID when relevant.
  --kind VALUE          bug or suggestion. Defaults to bug.
  --output-dir DIR      Where to write the JSON and Markdown files.

Agent pattern:
  relato prepare \
    --title "Foundation Models framework: add first-class video input support" \
    --description "$REPORT_BODY" \
    --snapshot ./evidence.md \
    --kind suggestion \
    --output-dir /tmp/relato-report

  sed -n '1,220p' /tmp/relato-report/feedback-submission.md
  relato submit --payload /tmp/relato-report/feedback-submission.json --dry-run
```

### `relato help submit`

```sh
relato submit: open/fill Feedback Assistant and optionally click native Submit

Usage:
  relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--verify-wait-seconds N] [--db PATH] [--confirm] [--verify-store] [--dry-run]

Default behavior:
  Without `--confirm`, this opens Feedback Assistant, fills the visible native
  form from the JSON payload, and stops before the Submit click.

Confirmation:
  --confirm             Clicks the visible native Submit button through
                        Accessibility automation. Use only after explicit
                        user confirmation at action time.

Verification:
  --verify-store        Reads the local Feedback Assistant store before/after
                        the handoff and prints local deltas.
  --db PATH             Override the local Feedback Assistant SQLite path.
  --dry-run             Print the planned native handoff without opening,
                        filling, attaching, or submitting.

Native form reality:
  Apple can add topic-specific required fields, popups, diagnostics, or log
  gathering. Agents should inspect the visible app before `--confirm`; the
  local store check is useful evidence but not a server-side receipt.
  RelatoKit uses an Objective-C Accessibility/CoreGraphics engine for native UI automation.
  Text is routed through process-targeted CoreGraphics events. Snapshot attachments
  are staged into the local Feedback Assistant draft folder after the native draft
  exists, avoiding the foreground-only Add Attachment picker. Foreground fallback is
  opt-in with RELATO_ALLOW_FOREGROUND_FALLBACK=1 for local experiments.

Agent pattern:
  relato submit --payload feedback-submission.json --dry-run --confirm
  relato submit --payload feedback-submission.json --select-popups
  # inspect native UI and satisfy Apple-only fields
  relato submit --payload feedback-submission.json --confirm --verify-store
  relato store list --limit 10
  relato store uploads --limit 10
```

### `relato help fill`

```sh
relato fill: fill the currently open Feedback Assistant draft

Usage:
  relato fill [--payload PATH] [--select-popups]

Notes:
  This does not open a new route and does not submit. It is useful when an
  agent has already navigated the native app, manually selected a topic, or
  needs to retry the visible form fill after changing native-only fields.

  --select-popups asks the AX driver to select known area/type popups. Some
  Apple forms use topic-specific popup labels and supported values, so
  inspect the native UI afterward.
```

### `relato help store`

```sh
relato store: inspect the local Feedback Assistant store

Usage:
  relato store summary [--db PATH]
  relato store list [--limit N] [--db PATH]
  relato store uploads [--limit N] [--db PATH]

Agent pattern:
  relato store summary
  relato store list --limit 10
  relato store uploads --limit 10

Notes:
  Store reads are local evidence only. They can show drafts, recent items,
  and upload tasks, but they are not Apple server receipts.
```

## Scripting Tips

- Use `relato submit --dry-run` before `--confirm` to preview the native handoff plan.
- Treat the JSON payload as the source of truth; regenerate it instead of hand-editing unless you know the schema.
- Use the Markdown payload to review the report body and stage supporting evidence.
- Use `relato open ROUTE --print-only` when you only need the Feedback Assistant URL.
- Use `relato store summary` and `relato store list` for local verification after native submission.
- Treat local store verification as local evidence, not an Apple server receipt.
