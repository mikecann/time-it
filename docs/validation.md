# Validation on 5 October 2026

- 14 Swift tests pass: atomic local storage, timer restart recovery, failed disk writes, midnight totals, CSV formula escaping, archived category history, revision acknowledgements, offline/reconnect retries, stopping during upload, upload dependency order, and independent download cursors, and avoiding idle history transfers.
- Five backend protocol tests pass: authentication, bounds and field validation, default category protection, duplicate retries, and conflict order.
- Installed `/Users/m5-mike/Applications/Time It.app` checked through native UI: start Convex, quit while running, relaunch and recover elapsed time, stop, add Personal, start Personal, stop through the taskbar, and confirm the next quick default is Convex.
- Taskbar integration: 315 Swift and 12 Python tests pass, shell syntax checks pass. Installed taskbar starts and stops the actual Time It app. Existing settings and signing identity are retained.
- The four agent-created timer entries were removed after QA. A temporary local backup was retained outside Git. Personal and Convex categories remain.

## Australian backend and installed app

Mike approved the proposed two-table schema on 5 October 2026. The approved schema and internal functions are deployed and strictly typechecked.

Management API metadata confirms exactly two deployments, both default deployments in `aws-ap-southeast-2`:

- Development `dev/au`: `cheery-minnow-636`.
- Production `live-au`: `academic-elephant-1`.

The two unused US deployments were verified empty and removed before time data was uploaded. Production is connected to the installed Mac app, with the key in Keychain. The private bootstrap file was removed by the app after successful setup.

Both Australian HTTP endpoints passed no-key and wrong-key rejection (401), malformed-body rejection (400), oversized-body rejection (413), and authenticated sync (200).

A harness using the actual Swift store, sync engine and HTTP client passed simulated offline start, restart and stop, followed by live Sydney development upload. The server committed the first request but the harness discarded its response to simulate a dropped connection. Retrying produced exactly one record with matching timestamps and revision, then uploaded its deletion tombstone. This did not disconnect the Mac's network.

The installed app was separately checked through its real UI: start Convex, wait for automatic sync, stop, and inspect its Sydney production URL and Everything synced state. Production returned the exact locally saved ID, revision and timestamps. That QA entry was soft-deleted locally and remotely; no pending changes or running timer remained. The existing Personal and Convex categories were preserved.

`swift test`, `npm test`, and `npm run typecheck` pass. CI now also checks backend types against the committed generated schema types.

## Menu bar visibility fix

The original AppKit status item reported visible in-process, and macOS allowed Time It in Menu Bar settings, but Mike confirmed the timer icon was absent. Restarting the app did not resolve it. The Mac runs Tahoe 26.6.2 (25G83).

Time It now uses a SwiftUI `MenuBarExtra`, the same mechanism used by the visible Meeting Archive app. The installed build passed all 14 Swift tests, and Mike confirmed the new timer icon appeared on 5 October 2026. Its menu offers Start Convex Timer or Stop Timer first, followed by Open Time It, Sync Now and Quit. The taskbar widget and URL controls are retained.

## Reports and Clockify import preparation

- 24 Swift tests pass, including local-midnight splitting, a 23-hour Sydney DST day, category filtering, tombstones, active timers, overlap totals, month grouping and empty periods.
- Import tests cover an unchanged running timer, a complete pre-import backup, category reuse, edited and deleted imported sessions, failed atomic writes, and 205 imported sessions surviving an offline restart before draining three sync batches without duplicates.
- Four exporter tests pass for exact timestamps, source descriptions and labels, skipped running Clockify timers, stable IDs, pagination through a short non-final page, and rejecting repeated pages.
- The five backend tests and backend typecheck pass. The deployed schema is unchanged.
- Installed app checked with the existing real timer running: Reports shows the live total, category ring, weekday profile and activity grid; selecting an empty category shows zero totals and the empty state. The original timer ID, start timestamp and revision remain unchanged across installation, with no pending changes.
- Clockify's signed-in personal workspace is accessible, but CSV export requires an upgrade and the account has no API key. The user was asked to create an API key. No Clockify history has been imported yet, and actual API export and production import verification remain pending that credential.
