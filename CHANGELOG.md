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
