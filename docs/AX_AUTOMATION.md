# AX Automation

RelatoKit uses macOS Accessibility APIs for native Feedback Assistant automation. The native form driver is implemented in Objective-C with `AXUIElement`, CoreGraphics events, and local fallbacks for native controls Feedback Assistant does not expose cleanly.

The AX driver works by:

1. Resolving Feedback Assistant by bundle identifier.
2. Reading windows and descendants from the Accessibility tree.
3. Matching controls by role, title, description, and value.
4. Attempting text fields and text areas through `AXValue`.
5. Trying named actions such as `AXPress` and `AXShowMenu` before synthetic input.
6. Routing text through public process-targeted CoreGraphics events with `CGEventPostToPid`.
7. Using SkyLight per-PID event posting for stubborn controls that reject public process-targeted events.
8. Staging local snapshots into the active Feedback Assistant draft folder after the native draft exists.
9. Keeping the Add Attachment picker path behind `RELATO_ALLOW_FOREGROUND_FALLBACK=1` for local experiments.
10. Stopping before final submission unless `--confirm` is explicitly provided.

## What AX Can Do

AX can drive many native controls without AppleScript:

- set title and description fields
- set bundle identifier fields when the form exposes them
- choose topic rows
- press Continue and Submit buttons
- select exposed pop-up menu items
- stage local evidence files into Feedback Assistant's local draft folder

## Practical Limits

AX is still native UI automation. It depends on the target app exposing useful Accessibility elements. Feedback Assistant can expose settable text values that echo through AX without committing into the visible SwiftUI form while inactive, so RelatoKit does not trust AX readback alone. It follows the public background keyboard pattern used by macOS automation projects: focus the target AX element, then send scoped CoreGraphics keyboard events directly to Feedback Assistant's process ID.

If the process-targeted path fails, RelatoKit fails closed by default. For local experiments, `RELATO_ALLOW_FOREGROUND_FALLBACK=1` re-enables foreground fallbacks, but the production CLI should preserve the user's current app and report the unsupported native-control boundary.

Some forms do not support every report kind. For example, a macOS form can accept `Incorrect/Unexpected Behavior` while rejecting `Suggestion` for its type popup. In those cases RelatoKit reports the failing native value instead of pretending the form was completed.

Local file attachments use draft-folder staging by default. Once Feedback Assistant creates a draft, RelatoKit copies the snapshot into `~/Library/Group Containers/group.com.apple.feedback/Library/Drafts/FB/<draft-id>/` and prints the staged path. The native Add Attachment > `Choose File...` picker path is still useful for local experiments, but it is behind `RELATO_ALLOW_FOREGROUND_FALLBACK=1` because Feedback Assistant does not reliably open that transient menu while inactive.

For fully isolated automation that never interrupts the user's primary desktop, run the native workflow in a separate macOS GUI session or virtual machine. RelatoKit can automate the app there through the same AX path.
