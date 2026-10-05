# Proposed Convex data model

Pending Mike's manual approval. No Convex schema has been created or deployed.

Time It is a personal, single-owner app. The Mac keeps a durable local store and an outbox. Network sync never blocks starting or stopping a timer.

Two new tables in a new, isolated Convex project:

- `categories`: `clientId` (stable UUID or built-in `convex`), `name`, `color`, `archived`, `revision`, `deviceId`, `updatedAt`. Indexed by `clientId`. Convex is the built-in default and cannot be archived.
- `entries`: `clientId` (stable UUID), `categoryId` (category client ID), `note`, `startedAt`, optional `endedAt`, `deleted`, `revision`, `deviceId`, `updatedAt`. Indexed by `clientId`. Timestamps are UTC milliseconds; durations and day boundaries are calculated on the Mac. Deletion is a tombstone so an offline device cannot resurrect an entry.

Records are sent in bounded batches through a bearer-authenticated HTTP action. Only internal Convex queries and mutations can access tables. A randomly generated personal sync secret lives in macOS Keychain and the isolated Convex environment, never in Git. There is no public unauthenticated access to time records.

The server acknowledges individual record revisions. Lost responses can be retried safely using stable record IDs. If the user edits during a request, acknowledging the older revision cannot clear the newer pending edit. Server conflict order is revision, then device ID for equal revisions. One Mac is the primary target; simultaneous timers on multiple Macs are not coordinated offline.

Local saves are atomic. Failed writes leave the previous state intact and show an error. Failed sync leaves the outbox intact and retries on reconnection, launch, and a periodic timer. Pending local edits take priority over downloaded snapshots until acknowledged.
