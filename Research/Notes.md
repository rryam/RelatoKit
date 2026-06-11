# Research Notes

`feedbackd_probe.m` is an exploratory Objective-C probe for Feedback Assistant private framework discovery.

It is intentionally not part of the normal SwiftPM build. The normal `relato` command should stay focused on local read-only inspection, report preparation, native app launch, and Accessibility handoff.

The first live XPC spike against `com.apple.feedbackd.centralized-feedback` failed at listener level with an entitlement refusal. That is the boundary this package should respect publicly.

FeedbackCore was also inspected as a possible local model path. A standalone Objective-C probe can load `/System/Library/PrivateFrameworks/FeedbackCore.framework` and inspect `FBKData`, `FBKDraftingController`, `FBKFormResponse`, `FBKAnswer`, `FBKQuestion`, and `FBKLaunchAction`. Embedding an Info.plist with `FBKUsePersistentStore=true` makes `FBKData` select the real Feedback Assistant SQLite store instead of its default in-memory store.

That path is not production-safe. A live draft-creation probe against `FBKDraftingController` was not stable outside Feedback Assistant's app session and reset the local SQLite store to an empty database during testing. The store was restored from a pre-probe backup, but this is too destructive to ship as the default CLI path.

Build manually when researching:

```sh
clang -fobjc-arc -framework Foundation Research/feedbackd_probe.m -o /tmp/feedbackd_probe
/tmp/feedbackd_probe inspect
/tmp/feedbackd_probe fetch-counts seedx:xcode
/tmp/feedbackd_probe launch-action 'https://feedbackassistant.apple.com/new?title=Hello'
```
