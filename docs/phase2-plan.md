# PasteDock Phase 2 Plan

## 1. Summary

The two primary goals of Phase 2 are to complete the following first:

1. iCloud-based text history synchronization
2. Multi-label-based history classification and filtering

The Bottom Sheet transition has high user impact but also high structural impact, so it is separated into a follow-up stage (Phase 2B).

- Document baseline date: 2026-02-15
- Priority: `Sync + Label` first, `Bottom Sheet` later

## 2. Scope

### 2.1 In Scope (Phase 2A)

1. Synchronization based on CloudKit private DB
2. Sync targets: metadata + text payload
3. Label CRUD and item-label many-to-many mapping
4. Label-based filtering in Quick Picker
5. Offline-first behavior + eventual sync recovery

### 2.2 Out of Scope (Phase 2A)

1. iCloud sync for image/file payloads
2. Collaborative shared board
3. Full Bottom Sheet UI migration

## 3. Milestones

### 3.1 Phase 2A-1: Sync Foundation

1. Keep local SQLite as source of truth
2. Use sync worker to upload local changes + apply remote changes
3. Conflict policy: `updatedAt`-based LWW (`originDeviceId` tie-break on timestamp ties)
4. Deletion propagation: use tombstones
5. Retry on failure: exponential backoff

### 3.2 Phase 2A-2: Label Management

1. Add label/join tables
2. Create/rename/delete/assign labels
3. Apply search query + label filters together
4. On label deletion, keep the item and remove only the association

### 3.3 Phase 2B: Bottom Sheet UX

1. Migrate from `NSPopover` to `NSPanel/NSWindow`
2. Apply motion rising from the dock-adjacent bottom area
3. Keep existing shortcut/keyboard navigation/execution behavior 100% compatible

## 4. Public Interface Changes

### 4.1 ClipboardItem

Add these fields:

- `updatedAt: Date`
- `deletedAt: Date?`
- `originDeviceId: String`

### 4.2 New Types

1. `Label`
   - `id`, `name`, `colorHex`, `createdAt`, `updatedAt`
2. `ClipboardItemLabel`
   - `itemId`, `labelId`, `createdAt`
3. `SyncState`
   - `idle`, `syncing`, `error(lastErrorCode)`

### 4.3 HistoryStore API

Keep existing APIs and extend with:

1. `upsert(item:)`
2. `markDeleted(id:at:)`
3. `labels()`
4. `createLabel(name:colorHex:)`
5. `renameLabel(id:name:)`
6. `deleteLabel(id:)`
7. `setLabels(itemId:labelIds:)`
8. `search(query:labelIds:limit:)`

### 4.4 Settings

Add these settings:

- `syncEnabled: Bool` (default `true`)
- `syncOnMeteredNetwork: Bool` (default `true`)
- `bottomSheetEnabled: Bool` (Phase 2B feature flag, default `false`)

## 5. Data & Migration

### 5.1 Schema Updates

1. `clipboard_items`
   - add `updated_at`
   - add `deleted_at`
   - add `origin_device_id`
2. new `labels`
3. new `item_labels`
4. new `sync_cursor`
5. new `sync_tombstones`

### 5.2 Indexes

1. `clipboard_items(updated_at)`
2. `clipboard_items(deleted_at)`
3. `labels(name)` unique
4. `item_labels(item_id, label_id)` unique

### 5.3 Migration Rules

1. Existing items: `updated_at = created_at`
2. Existing items: `deleted_at = NULL`
3. Existing items: `origin_device_id = currentDeviceId`

## 6. Behavior Rules

### 6.1 Sync Triggers

1. One-time pull on app startup
2. Debounced upload after local changes
3. Periodic background pull

### 6.2 Failure Handling

1. Retry with backoff on CloudKit errors
2. Local operations always succeed first
3. Sync failures are surfaced via status + logs

### 6.3 Label Filtering

1. Default view: all items
2. Label filter: OR matching
3. Search query + label filters can be applied together

## 7. Testing Plan

### 7.1 Unit Tests

1. Validate LWW conflict resolution
2. Validate tombstone deletion propagation
3. Validate label CRUD/association consistency
4. Validate label-filter search accuracy

### 7.2 Integration Tests

1. Offline creation -> online recovery sync
2. Concurrent multi-device edit conflict handling
3. Restore/paste behavior while label filters are active

### 7.3 Regression

1. Existing `capture -> search -> restoreAndPaste` path integrity
2. Query performance degradation check with 10k records

## 8. Acceptance Criteria

1. Text history can sync across devices using the same Apple ID
2. Items can be immediately filtered by labels
3. Local capture/restore usability remains intact during sync failures
4. No regressions in existing shortcut and execution flows

## 9. Backlog Candidates

1. Label auto-rules (`sourceBundleId`, regex)
2. Favorite presets (pin + label combinations)
3. Snippet templates
4. JSON backup/restore
5. Advanced search (date/app/type/label combinations)

## 10. Assumptions & Defaults

1. iCloud supports only user private DB
2. Phase 2A prioritizes text-only sync
3. Conflicts use automatic LWW without manual merge
4. Bottom Sheet is introduced gradually via feature flag
