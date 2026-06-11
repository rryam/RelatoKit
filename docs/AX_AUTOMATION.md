# AX Automation

RelatoKit uses macOS Accessibility APIs for native Feedback Assistant automation. The native form driver is implemented in Objective-C with `AXUIElement` and CoreGraphics events; there is no bundled AppleScript automation engine.

The AX driver works by:

1. Resolving Feedback Assistant by bundle identifier.
2. Reading windows and descendants from the Accessibility tree.
3. Matching controls by role, title, description, and value.
4. Attempting text fields and text areas through `AXValue`.
5. Falling back to foreground CoreGraphics paste events when Feedback Assistant does not commit background AX text writes.
6. Pressing native buttons, rows, and menu items through `AXPress`.
7. Stopping before final submission unless `--confirm` is explicitly provided.

## What AX Can Do

AX can drive many native controls without AppleScript:

- set title and description fields
- set bundle identifier fields when the form exposes them
- choose topic rows
- press Continue and Submit buttons
- select exposed pop-up menu items
- interact with exposed attachment picker controls when Feedback Assistant opens a real file picker

## Practical Limits

AX is still native UI automation. It depends on the target app exposing useful, settable Accessibility elements. Feedback Assistant currently exposes settable text values that can echo through AX without committing into the visible SwiftUI form while inactive. RelatoKit detects that and uses a foreground public-API fallback for text entry.

Some forms do not support every report kind. For example, a macOS form can accept `Incorrect/Unexpected Behavior` while rejecting `Suggestion` for its type popup. In those cases RelatoKit reports the failing native value instead of pretending the form was completed.

Local file attachments are form-dependent. On the tested macOS form, the visible Add Attachment control opened an Add Device Diagnostics sheet rather than a file picker, so RelatoKit fails closed with `Native file attachment picker did not open`.

For fully isolated automation that never interrupts the user's primary desktop, run the native workflow in a separate macOS GUI session or virtual machine. RelatoKit can automate the app there through the same AX path.
