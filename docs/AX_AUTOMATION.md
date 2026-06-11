# AX Automation

RelatoKit uses macOS Accessibility APIs for native Feedback Assistant automation. The native form driver is implemented in Objective-C with `AXUIElement` and fail-closed handling for native controls Feedback Assistant does not expose cleanly.

The AX driver works by:

1. Resolving Feedback Assistant by bundle identifier.
2. Reading windows and descendants from the Accessibility tree.
3. Matching controls by role, title, description, and value.
4. Attempting text fields and text areas through `AXValue`.
5. Using passive `AXValue` writes for text fields and exposed popups.
6. Avoiding synthetic mouse events, keyboard events, pasteboard writes, and focus reassignment.
7. Failing closed when a native control requires active focus or pointer ownership.
8. Staging local snapshots into the active Feedback Assistant draft folder after the native draft exists.
9. Opening Feedback Assistant without activation and hiding it after launch/fill.
10. Failing closed instead of foregrounding Feedback Assistant when a native control refuses background automation.
11. Stopping before final submission unless `--confirm` is explicitly provided.

## What AX Can Do

AX can drive many native controls without AppleScript:

- set title and description fields
- set bundle identifier fields when the form exposes them
- choose topic rows
- press Continue and Submit buttons
- passively set exposed pop-up values when Feedback Assistant accepts direct AX values
- stage local evidence files into Feedback Assistant's local draft folder

## Practical Limits

AX is still native UI automation. It depends on the target app exposing useful Accessibility elements. RelatoKit intentionally does not focus target fields, synthesize keyboard input, move the pointer, or use the pasteboard during the default fill path. That keeps the user's current text insertion focus intact, but it means some Feedback Assistant controls can only be completed by the user in the native app.

If passive AX mutation fails, RelatoKit fails closed. The production CLI should preserve the user's current app and report the unsupported native-control boundary.

We tested the stronger macOS background-input pattern used by tools such as Cua and Peekaboo: SkyLight per-PID event posting, focus-without-raise, AX direct value setting, and process-targeted keyboard events. That route can mutate and render hidden Feedback Assistant text fields, but Feedback Assistant's SwiftUI popups expose no selectable children while hidden and did not accept hidden process-targeted keyboard selection. RelatoKit therefore keeps popups fail-closed instead of stealing focus.

Some forms do not support every report kind. For example, a macOS form can accept `Incorrect/Unexpected Behavior` while rejecting `Suggestion` for its type popup. In those cases RelatoKit reports the failing native value instead of pretending the form was completed.

Local file attachments use draft-folder staging. Once Feedback Assistant creates a draft, RelatoKit copies the snapshot into `~/Library/Group Containers/group.com.apple.feedback/Library/Drafts/FB/<draft-id>/` and prints the staged path. RelatoKit does not drive the visible Add Attachment > `Choose File...` picker because Feedback Assistant does not reliably open that transient menu while inactive.

For fully isolated automation that never interrupts the user's primary desktop, run the native workflow in a separate macOS GUI session or virtual machine. RelatoKit can automate the app there through the same AX path.
