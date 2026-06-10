# Research Notes

`feedbackd_probe.m` is an exploratory Objective-C probe for Feedback Assistant private framework discovery.

It is intentionally not part of the normal SwiftPM build. The normal `relato` command should stay focused on local read-only inspection, report preparation, native app launch, and Accessibility handoff.

The first live XPC spike against `com.apple.feedbackd.centralized-feedback` failed at listener level with an entitlement refusal. That is the boundary this package should respect publicly.

Build manually when researching:

```sh
clang -fobjc-arc -framework Foundation Research/feedbackd_probe.m -o /tmp/feedbackd_probe
/tmp/feedbackd_probe inspect
/tmp/feedbackd_probe fetch-counts seedx:xcode
/tmp/feedbackd_probe launch-action 'https://feedbackassistant.apple.com/new?title=Hello'
```
