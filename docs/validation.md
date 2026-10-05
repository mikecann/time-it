# Validation on 5 October 2026

- 13 Swift tests pass: atomic local storage, timer restart recovery, failed disk writes, midnight totals, CSV formula escaping, archived category history, revision acknowledgements, offline/reconnect retries, stopping during upload, upload dependency order, and independent download cursors.
- Five backend protocol tests pass: authentication, bounds and field validation, default category protection, duplicate retries, and conflict order.
- Installed `/Users/m5-mike/Applications/Time It.app` checked through native UI: start Convex, quit while running, relaunch and recover elapsed time, stop, add Personal, start Personal, stop through the taskbar, and confirm the next quick default is Convex.
- Taskbar integration: 315 Swift and 12 Python tests pass, shell syntax checks pass. Installed taskbar starts and stops the actual Time It app. Existing settings and signing identity are retained.
- The four agent-created timer entries were removed after QA. A temporary local backup was retained outside Git. Personal and Convex categories remain.

## Pending schema approval

The Personal Convex team contains the isolated `time-it` project with development and production deployments. Both databases have no tables. No sync key has been created, and no time data has been uploaded.

`convex/schema.ts` is deliberately absent pending Mike's manual approval. The backend source and protocol checks are prepared. Full backend typechecking currently reports the three missing `by_clientId` indexes because generated types have no schema yet. Cloud deployment, endpoint authentication checks, and a live offline-to-online round trip must be verified after approval.
