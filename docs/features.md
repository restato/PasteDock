# PasteDock Features

## 1. Product Overview

`PasteDock` is a macOS 14+ menu bar clipboard manager demo app.  
Its primary goal is to reliably persist recent clipboard history and enable fast restore/paste operations from the Quick Picker.

The project is split into two layers:

- `ClipboardCore`: domain logic for capture/storage/restore, permission state, toasts, and related services
- `PasteDock`: menu bar UI, shortcuts, system clipboard I/O, and runtime orchestration

## 2. Capture Pipeline

Clipboard changes are monitored periodically using `NSPasteboard.changeCount`.

- Default polling interval: `250ms` (`Settings.monitoringIntervalMs`)
- Effective minimum interval: `50ms` (internal service clamp)

Capture order follows this priority:

1. File (`NSPasteboard` file URLs)
2. Text (`.string`)
3. Image (`.png` or `.tiff` converted to PNG)

Captured input is passed to `CapturePipeline`, where these policies are applied:

- Skip excluded apps: `Settings.excludedBundleIds`
- Skip sensitive data: pattern checks when `Settings.privacyFilterEnabled` is enabled
- Skip consecutive duplicates: do not save if the same as the last item's `contentHash`
- Handle invalid input:
  - empty text
  - empty image bytes
  - empty file list

After successful save, retention limits are enforced immediately.

- Default limits: `maxItems=500`, `maxBytes=2GB`
- On overflow: remove oldest items first

## 3. Store and Payloads

The default history backend is `GRDBHistoryStore` (SQLite), with fallback to `InMemoryHistoryStore` on failure.

- DB: `history.sqlite`
- Text payload: `texts/<uuid>.txt`
- Image payload: `images/<uuid>.png`
- File payload: `files/<uuid>.json` (`FileClipboardPayload.paths`)

Key metadata stored in `ClipboardItem`:

- `id`, `createdAt`
- `kind` (`text`, `image`, `file`)
- `previewText`
- `contentHash`
- `byteSize`
- `sourceBundleId`
- `payloadPath`

Search behavior:

- Empty query: return newest first
- Non-empty query: case-insensitive containment search over `previewText`
- `Settings.quickPickerResultLimit` stays aligned with `maxItems`

## 4. Quick Picker and Input UX

The menu bar panel has `Quick` and `Settings` tabs.

Core Quick Picker behavior:

- Automatic initial selection
- Immediate refresh on query changes
- Keyboard interactions:
  - Number input: select by index (supports multi-digit input buffer)
  - `Enter`: execute selected item or top item
  - `↑` / `↓`: move selection
  - `Cmd+Backspace`: delete selected item
  - `Esc`: close panel
- Mouse interactions:
  - Left click: execute immediately (restore/paste)
  - Right click or `Ctrl+click`: select only (no execution)
- Right-side preview supports `text`, `image`, and `file`
- Preview target rule: hovered item first, otherwise current selection
- File preview: list + selected file metadata + `Reveal` / `Copy Path` actions
- Item columns: `Source` (app name) / `Time` (`absolute time · relative time`)

## 4.1 Menu Bar Icon

The menu bar (status bar) icon uses bundled resource `menuBarTemplate.png`.

- Icon type: monochrome template (`isTemplate = true`)
- Source image: `assets/icon/source.png`
- Generation script: `bash scripts/generate-app-icon.sh`
- Missing resource fallback: SF Symbol icon

## 5. Restore and Auto Paste

`PasteActionService` provides two paths: `restore` and `restoreAndPaste`.

Shared restore behavior:

- Text: read payload file and write string to pasteboard
- Image: read PNG and write as `NSImage` or raw PNG
- File: read payload JSON and write file paths as pasteboard URLs

When restoring files, missing source files are treated as failure:

- Failure reason: `file_missing`
- User message: `Restore failed (file missing)`

Auto paste (`Cmd+V` event injection):

- With Accessibility permission: activate target app then send event
- Without permission: fallback to `Restored only (permission needed)`
- If auto paste fails: fallback to `Restored only`

## 6. Permission/Settings Health Check (Setup Check)

`PermissionHealthService` evaluates the following statuses:

1. Accessibility
2. Login Item
3. Sparkle Update Channel

Each item has `ready` or `actionRequired` status and provides a system settings action when needed.

Accessibility diagnostics data:

- `isTrusted`
- `bundleId`
- `appPath`
- `isBundled`
- `guidanceReason`

Permission-failure reminder banner policy:

- Show banner after 3 consecutive identical failure reasons
- Reset counter after a success
- Disabled when `Settings.permissionReminderEnabled == false`

## 7. User Feedback and Logs

Toasts (`OperationToastService`) are managed with a FIFO queue.

- Styles: success/info/warning/error
- No toast output when `Settings.showOperationToasts == false`

Local logs (`LocalLogService`) are recorded in JSONL format.

- Events: `capture`, `retention`, etc.
- Results: `saved`, `skipped`, `failed`, `trimmed`
- Includes rotation policy and backup file management

Runtime log file (app layer):

- `~/Library/Application Support/com-justdoit-pastedock/logs/runtime.log`

## 8. Default Settings

`Settings` defaults:

- `maxItems = 500`
- `maxBytes = 2 * 1024 * 1024 * 1024`
- `quickPickerShortcut = "Cmd+Shift+V"`
- `autoPasteEnabled = true`
- `launchAtLogin = true`
- `privacyFilterEnabled = true`
- `showOperationToasts = true`
- `permissionReminderEnabled = true`
- `monitoringIntervalMs = 250`
- `quickPickerResultLimit = maxItems` (default 500)

## 9. Current Scope Constraints

- Supported platform: macOS 14+
- Deployment target app is a menu bar-focused demo app
- External telemetry/cloud sync is out of current scope
- Deployment automation is based on the Developer ID + Notary web distribution flow
