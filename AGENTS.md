# Time It

Native macOS SwiftUI/AppKit app with a Convex sync backend. Local state is authoritative while offline. Never wait for the network before saving a timer action.

- Convex schema changes don't need Mike's approval. Make them as the work needs and say what changed.
- Preserve stable entry IDs, revision acknowledgements, tombstones, and atomic disk writes.
- Never commit credentials, local recordings, or personal time data.
- Run `swift test` and backend checks for sync changes. Verify the installed app for UI changes.
- No eyebrows, kickers, or em dashes in UI or writing.
- PR descriptions start with `## Why`.
