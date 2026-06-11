# Security Policy

RelatoKit handles local Feedback Assistant metadata and may pass local attachment paths to the native Feedback Assistant app.

Do not report security issues publicly if they expose:

- private Apple account information
- unpublished feedback contents
- local file paths that reveal confidential projects
- logs or attachments containing credentials

Open a private security advisory on GitHub when possible.

## Project Boundary

RelatoKit does not accept contributions that bypass Apple entitlements, disable platform security, forge Apple credentials, inject into Apple-signed processes, or implement private headless submission. Local automation must use the signed-in Feedback Assistant app, its local draft store, and explicit native Submit action; it must not replace Apple's authentication, diagnostics, review, or submission flows.
