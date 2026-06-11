# Background Automation

RelatoKit uses two different macOS automation layers:

- AppleScript through System Events for visible UI choreography.
- Accessibility APIs for low-interruption reads and writes where the target control supports direct attribute updates.

Those layers have different limits. AppleScript keyboard and pointer-style automation is tied to the active desktop. If a step depends on typing keys, choosing a menu by keyboard, opening a file picker, or pressing a button that Apple expects the user to review, it should be treated as foreground UI automation.

Direct Apple Events are different: a scriptable app can expose its own object model and allow background changes without UI. That is app-specific automation, not generic GUI automation. Feedback Assistant's useful submission controls are not exposed as a public scripting dictionary, so RelatoKit treats it as an Accessibility-driven native app workflow.

The background-safe path is lower level: find the target Accessibility element and set an attribute such as `AXValue` directly. That can work for ordinary text fields and text areas without stealing focus, but it depends on the target app exposing a settable Accessibility attribute. Pop-up menus, topic choosers, file pickers, and final submission controls often still require foreground review on the current desktop.

## RelatoKit Policy

`--background` means low-interruption, not headless submission.

Allowed:

- opening Feedback Assistant without activation
- filling background-safe text fields
- stopping before any action that needs foreground review

Rejected:

- `--background --select-popups`
- `--background --confirm`
- `--background` with attachments

For fully isolated automation, run the foreground workflow in a separate macOS GUI session or VM. The active desktop will still be used inside that isolated environment, but it will not take over the user's primary Mac session.

## Future Direction

The next robustness step is to replace more AppleScript field writes with a Swift `AXUIElement` driver:

1. Resolve the target app by bundle identifier.
2. Traverse windows and descendants through Accessibility attributes.
3. Match controls by role, description, title, and nearby labels.
4. Check whether `AXValue` is settable.
5. Set values directly when possible.
6. Fall back to foreground UI only for controls that require user-visible interaction.

This keeps the package useful for agents while staying inside macOS Accessibility boundaries.
