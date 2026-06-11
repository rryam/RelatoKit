# AX Automation

RelatoKit uses macOS Accessibility APIs for native Feedback Assistant automation. The native form driver is implemented in Swift with `AXUIElement`; there is no bundled AppleScript automation engine.

The AX driver works by:

1. Resolving Feedback Assistant by bundle identifier.
2. Reading windows and descendants from the Accessibility tree.
3. Matching controls by role, title, description, and value.
4. Setting text fields and text areas through `AXValue`.
5. Pressing native buttons, rows, and menu items through `AXPress`.
6. Stopping before final submission unless `--confirm` is explicitly provided.

## What AX Can Do

AX can drive many native controls without pretending to type into the active keyboard stream:

- set title and description fields
- set bundle identifier fields when the form exposes them
- choose topic rows
- press Continue and Submit buttons
- select exposed pop-up menu items
- interact with exposed attachment picker controls

## Practical Limits

AX is still native UI automation. It depends on the target app exposing useful, settable Accessibility elements. If Feedback Assistant changes a form, hides a picker field, or requires Apple-only diagnostic steps, RelatoKit reports the failing control instead of falling back to private APIs or synthetic AppleScript keystrokes.

For fully isolated automation that never interrupts the user's primary desktop, run the native workflow in a separate macOS GUI session or virtual machine. RelatoKit can automate the app there through the same AX path.
