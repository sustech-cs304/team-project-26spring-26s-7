# TravelPin Test Handoff

This document is the handoff note for continuing test work in Claude Code.

## Current State

The default Hypium suite in `frontend/entry/src/test/List.test.ets` now covers 35 passing tests.

### Already Implemented And Passing

- `MultipartFormDataTest`
- `ShareErrorMapperTest`
- `SharePreflightTest`
- `SharePhotoHelperTest`
- `ShareServiceTest`
- `RdbHelperTest`
- `TravelRepositoryTest`
- `MemoryNodeRepositoryTest`

### Production Test Seams Already Added

- `ShareService` exposes `createFormData()` and `sendRequest()` for request-level isolation.
- `SharePhotoHelper` exposes hook-based seams for file checks, sanitization, and temporary cleanup.
- `RdbHelper` exposes narrow testing hooks for fake predicates, fake time, and fake store injection.
- `TravelRepository` exposes narrow testing hooks for owner UID, time, and predicate creation.
- `MemoryNodeRepository` exposes narrow testing hooks for owner UID, time, predicate creation, and injected travel repository lookup.

## Already Covered

### Share Common

- Multipart boundary and payload construction for text-only bodies.
- Preflight blocking for empty node lists, invalid expiry, mismatched photo counts, cloud-only refs, and missing local files.
- Photo helper filtering, sanitization output, cleanup path handling, and cleanup selection.
- Publish request construction, replace-link fields, replay preference fields, fallback to `expiryHours`, backend error parsing, network error mapping, status error-envelope parsing, and revoke parsing.

### Rdb And Repository

- `RdbHelper`: uninitialized `getStore()`, scoped sync-state read/write, sync queue ordering and removal, and `wipeAllUserData()`.
- `TravelRepository`: create/read round-trip, cloud-backed update metadata transitions, and child-node cleanup before travel deletion.
- `MemoryNodeRepository`: node creation with next order assignment, moving nodes to a new travel with appended order, and reorder persistence with `pending_reorder`.

## Not Yet Designed

The following areas are still good candidates for the next light-integration pass.

### TravelRepository

- `getAllTravelsIncludingDeleted()`
- `findLocalIdByCloudId()`
- `updateSyncMetadata()`
- `upsertFromCloud()`
- `markDeletedByCloud()`
- `softDeleteTravel()`

### MemoryNodeRepository

- `getAllNodesIncludingDeleted()`
- `getNodeById()`
- `findLocalIdByCloudId()`
- `updateSyncMetadata()`
- `updatePhotoManifest()`
- `upsertFromCloud()`
- `markDeletedByCloud()`
- `softDeleteNode()`
- `deleteNode()`

### UI And Scenario Tests

- Launch smoke
- Map home smoke
- Node create/edit smoke
- Trip detail smoke
- Share page publish smoke

## How To Generate New Tests

Use this sequence when adding new tests in this repo.

1. Pick the smallest stable behavior to isolate first.
2. Prefer a pure unit test if the logic can run without I/O.
3. Add a light-integration seam only when local Hypium cannot isolate the dependency.
4. Reuse a shared fake support file when multiple repository tests need the same fake store, fake predicates, or fake time.
5. Put the new suite under `frontend/entry/src/test/unit/...` or `frontend/entry/src/test/integration/...`.
6. Register the new suite in `frontend/entry/src/test/List.test.ets`.
7. Keep the test deterministic. If time matters, inject it through a fake time provider.

### ArkTS Test Rules Used Here

- Avoid `any`, `unknown`, and indexed property access in tests.
- Prefer explicit classes for fakes instead of loose object literals.
- Avoid method reassignment on production classes. Use hook objects or narrow factory seams instead.
- Keep assertions simple and local to the behavior under test.
- Restore every injected hook in `finally`.

## Local Test Flow

Use these commands from the repo root.

```powershell
cd frontend
powershell -ExecutionPolicy Bypass -File build.ps1 test
git diff --check
```

If ArkTS code changed and a full build is needed, run:

```powershell
cd frontend
powershell -ExecutionPolicy Bypass -File build.ps1 --mode module -p module=entry@default assembleHap
```

### What To Check After The Run

- Test count and failures in `frontend/entry/.test/default/intermediates/test/coverage_data/test_result.txt`
- Any new compiler errors in the console output
- Existing warnings that are unrelated to the current change
- `git diff --check` for whitespace or line-ending issues

## Suggested Next Work

1. Add the remaining `TravelRepository` light-integration tests for `softDeleteTravel()` and cloud-sync helpers.
2. Add the remaining `MemoryNodeRepository` light-integration tests for soft delete, delete, and cloud-sync helpers.
3. Only after the data layer is stable, start the first UI smoke tests.
