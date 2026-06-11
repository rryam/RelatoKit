# Changelog

All notable changes to RelatoKit will be documented in this file.

## Unreleased

- Added the initial `RelatoKit` Swift package and `relato` CLI.
- Added read-only local Feedback Assistant store inspection.
- Added category inference from title, description, and bundle identifier.
- Added JSON and Markdown payload preparation.
- Added native Feedback Assistant route launching.
- Added Accessibility-assisted native form filling.
- Added explicit `relato submit --confirm` native UI submission handoff.
- Added `relato submit --dry-run` for previewing the native handoff plan.
- Added best-effort local store verification after native submission.
- Added generated command reference, CI, support, security, and contributing docs.
- Improved native form filling for the Feedback Assistant topic chooser, loading state, popups, bundle ID fields, and local attachments.
- Improved CLI validation for unknown arguments, invalid `--kind` values, numeric options, malformed payloads, and non-Feedback Assistant payload URLs.
- Added URL and route tests for prepared feedback payloads.
- Expanded `relato --help`, topic help, and generated command docs for agent-oriented payload and submit workflows.
- Added experimental `--background` support for low-interruption native open and text-field filling, with guardrails around foreground-only UI actions.
- Replaced the AppleScript native-fill engine with a Swift `AXUIElement` driver and removed the `--background` and `--script` CLI flags.
- Moved native Feedback Assistant automation to an Objective-C Accessibility/CoreGraphics engine and added fail-closed handling for unsupported local attachment pickers.
- Added process-targeted CoreGraphics text routing before foreground fallback, matching the public `CGEventPostToPid` background keyboard pattern used by macOS automation tools.
- Added background local attachment staging into Feedback Assistant draft folders, with the visible Add Attachment > Choose File path kept as an opt-in lab fallback.
- Added PID/window-routed CoreGraphics mouse events inspired by Peekaboo-style background input delivery.
