# RelatoKit

[![CI](https://github.com/rryam/RelatoKit/actions/workflows/ci.yml/badge.svg)](https://github.com/rryam/RelatoKit/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-6.0+-fa7343?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/macOS-14.0+-000000?style=flat&logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Local-first Swift tools for preparing Feedback Assistant reports.

RelatoKit (from the Portuguese `relato`, meaning report or account) provides a local-first Swift CLI and library for preparing Feedback Assistant reports on macOS. It can inspect the local Feedback Assistant store, generate structured report payloads, open Apple's native app, and assist with form entry through Accessibility automation.

RelatoKit keeps authentication, diagnostics, and final submission inside Feedback Assistant. It does not bypass entitlements, disable platform security, forge Apple credentials, or submit feedback without the explicit `--confirm` flag.

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
.build/release/relato version
```

Add the library to another Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/rryam/RelatoKit.git", branch: "main")
]
```

```swift
.product(name: "RelatoKit", package: "RelatoKit")
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

Submit through the native app with explicit confirmation:

```sh
relato submit --payload feedback-submission.json --dry-run
relato submit --payload feedback-submission.json --confirm
```

Without `--confirm`, `relato submit` opens and fills Feedback Assistant, then stops before clicking the native Submit button.

With `--confirm`, RelatoKit uses the signed-in native app to submit through the visible UI, then performs best-effort local store verification. This check can show local store changes and matching recent items, but it is not a server-side receipt from Apple.

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
relato submit [--payload PATH] [--select-popups] [--wait-seconds N] [--confirm] [--verify-store] [--dry-run]
relato version
```

## Current Status

RelatoKit is a pre-1.0 package focused on local store inspection, report preparation, native app launch, Accessibility-assisted form entry, explicit native UI submission, and best-effort local verification. `relato submit --confirm` is native app automation; it is not private headless submission.

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
make check
```

## Documentation

- [docs/COMMANDS.md](docs/COMMANDS.md) - generated command reference
- [CHANGELOG.md](CHANGELOG.md) - release notes
- [CONTRIBUTING.md](CONTRIBUTING.md) - development workflow
- [SUPPORT.md](SUPPORT.md) - support checklist
- [SECURITY.md](SECURITY.md) - security reporting and project boundary

## License

MIT

---

<p align="center">
  <sub>RelatoKit is an independent, unofficial tool and is not affiliated with, endorsed by, or sponsored by Apple Inc. Apple, macOS, Xcode, and Feedback Assistant are trademarks of Apple Inc.</sub>
</p>
