# RelatoKit

Local-first Swift tools for preparing Feedback Assistant reports.

RelatoKit (from the Portuguese `relato`, meaning report or account) helps you inspect local Feedback Assistant data, prepare a clean report payload, open Apple's native Feedback Assistant app, and hand off the boring form-filling bits to the Mac.

It keeps Feedback Assistant in charge of authentication, diagnostics, and final submission. RelatoKit does not bypass entitlements, disable platform security, forge Apple credentials, or submit feedback without the explicit `--confirm-submit` action.

```sh
relato prepare \
  --title "Xcode canvas stops updating after file rename" \
  --description "Steps, expected result, actual result." \
  --snapshot ./snapshot.png \
  --bundle-id com.apple.dt.Xcode \
  --kind bug

relato open-native --payload feedback-submission.json
relato fill --payload feedback-submission.json
```

## Requirements

- macOS 14.0+
- Swift 6.0+
- Xcode command line tools
- Feedback Assistant installed and signed in
- Accessibility permission for Terminal, if you use native form filling

## Installation

Build from source:

```sh
git clone https://github.com/rryam/RelatoKit.git
cd RelatoKit
swift build -c release
.build/release/relato --help
```

## What It Does

RelatoKit gives you a small command-line workflow around the native Feedback Assistant app:

- read-only inspection of the local Feedback Assistant store
- topic and area inference from title, description, and bundle identifier
- JSON and Markdown report preparation
- native Feedback Assistant route launching
- Accessibility-assisted title, description, bundle ID, and attachment handoff
- private-framework research notes kept outside the normal CLI surface

## First Commands

Inspect the local store:

```sh
relato store summary
relato store list --limit 20
relato store uploads
relato categories
```

Check routing and categorization:

```sh
relato routes
relato open new --print-only
relato categorize \
  --title "Xcode preview fails to refresh" \
  --description "The canvas stops updating after renaming a SwiftUI file." \
  --bundle-id com.apple.dt.Xcode
```

Prepare a report:

```sh
relato prepare \
  --title "Xcode preview fails to refresh" \
  --description "Steps to reproduce, expected result, and actual result." \
  --snapshot ./snapshot.png \
  --bundle-id com.apple.dt.Xcode \
  --kind bug
```

Open and fill the native app:

```sh
relato open-native --payload feedback-submission.json
relato fill --payload feedback-submission.json
```

Submit through the native app only when you mean it:

```sh
relato submit --payload feedback-submission.json --confirm-submit
```

Without `--confirm-submit`, `relato submit` opens and fills Feedback Assistant, then stops before clicking the native Submit button.

With `--confirm-submit`, RelatoKit still stays on Apple's side of the fence: it asks the signed-in native app to submit through the visible UI, then performs a best-effort local store verification. That check can show local store changes and matching recent items, but it is not an Apple server receipt.

## Commands

```sh
relato store summary [--db PATH]
relato store list [--limit N] [--db PATH]
relato store uploads [--limit N] [--db PATH]
relato categories [--db PATH]
relato categorize --title TEXT [--description TEXT] [--bundle-id ID]
relato prepare --title TEXT --description TEXT [--snapshot PATH] [--bundle-id ID] [--kind bug|suggestion] [--output-dir DIR]
relato routes
relato open ROUTE [--id ID] [--print-only]
relato open-native [--payload PATH]
relato fill [--payload PATH] [--select-popups] [--script PATH]
relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--confirm-submit] [--verify-store]
```

## Current Status

This is an early research package. The safe surface is intentionally boring: inspect, prepare, open, fill, hand off, and optionally click the visible native Submit button with an explicit flag. `relato submit --confirm-submit` is still native app automation; it is not private headless submission.

The package also includes `Research/feedbackd_probe.m`, an exploratory probe for Feedback Assistant private framework discovery. It is not part of the Swift package build. The first live XPC spike against `feedbackd` hit an entitlement refusal at listener level, and that boundary is respected by the public CLI.

## Non-Goals

- No entitlement bypass.
- No forged Apple credentials.
- No SIP or platform security workarounds.
- No background or headless submission to Apple.
- No redistribution of Apple private headers or copied framework code.

## Build

```sh
swift build
swift test
swift build -c release
```

## License

MIT
