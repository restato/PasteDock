## macOS Clipboard Manager v1 Final Plan (Continuation from Previous Thread, Decisions Applied)

### Summary
1. Goal: Deliver a `macOS 14+` menu bar app that persistently stores text/image clipboard history and provides a fast re-paste-centered UX.
2. Newly finalized key decisions:
- Quick Picker: `Spotlight-style centered popup`
- Selection trigger: `instant execution with number keys (1-9)`
- `Pin UI`: removed from v1 scope
3. Existing decisions kept as-is:
- Retention policy: max 500 items + total 2GB cap (delete oldest first on overflow)
- Excluded apps: default list + user editable
- Protection mode: skip save when sensitive patterns are detected
- Updates: Sparkle automatic updates starting in v1
- Language: English only
- Diagnostics: local logs only
- Launch: public distribution immediately
- Release automation: based on `/Users/direcision/Workspace/just-do-it/scripts/release-macos-spm.sh`

### Scope
1. Included
- Menu bar app + settings window
- Clipboard monitoring/storage (text, image)
- Search, delete, clear all
- Global shortcut `Cmd+Shift+V` to open centered popup Quick Picker
- Number-key immediate `restore + auto paste` (restore-only fallback when permission is missing)
- Launch at login
- Sparkle updates
2. Excluded
- iCloud/sync, OCR, AI classification, collaborative sharing
- External telemetry (Sentry/Crashlytics)

### Architecture/Modules
1. `ClipboardMonitor`: monitors `NSPasteboard.changeCount`.
2. `CapturePipeline`: type detection -> sensitive/excluded app checks -> dedupe -> save.
3. `HistoryStore` (SQLite+GRDB): CRUD/search/sort.
4. `RetentionManager`: enforces 500 items/2GB policy.
5. `QuickPickerController`: centered popup, search, instant number-key execution.
6. `PasteActionService`: `restore` and `restoreAndPaste` (permission-based branching).
7. `PrivacyPolicyService`: excluded app + sensitive pattern filtering.
8. `LaunchAtLoginService`, `UpdaterService(Sparkle)`, `LocalLogService`.

### Public Interface / Type Changes
1. `ClipboardItem`
- `id`, `createdAt`, `kind(text|image)`, `previewText`, `contentHash`, `byteSize`, `sourceBundleId`, `payloadPath`
- Change note: pin UI removed, but internal data structure kept for compatibility
2. `Settings`
- `maxItems`, `maxBytes`, `quickPickerShortcut`, `autoPasteEnabled`, `launchAtLogin`, `excludedBundleIds`, `privacyFilterEnabled`
3. Store API
- `save(item)`, `search(query, limit)`, `delete(id)`, `clearAll()`, `enforceLimits()`
4. Action API
- `restore(id)`, `restoreAndPaste(id)`
- Number-key path calls `restoreAndPaste(id)` by default, and automatically falls back to `restore(id)` when permissions are insufficient

### Data/Policy
1. Image originals are stored under `Application Support/<App>/images/<uuid>`, and DB stores metadata + path.
2. Consecutive duplicates (`contentHash`) are not re-saved.
3. Cleanup policy deletes oldest items first.

### Test Cases/Scenarios
1. Unit tests
- Sensitive pattern filter, excluded app filter, dedupe, 500/2GB retention logic, search sorting
2. Integration tests
- Text/image capture-restore
- Quick Picker trigger (`Cmd+Shift+V`) and immediate number-key execution
- Missing Accessibility permission fallback (restore-only)
- Persistence after app restart
3. Deployment/release tests
- Sparkle update (old -> new version)
- Notarized DMG installation and Gatekeeper pass
4. Acceptance criteria
- Restore/paste previous entries within 2 seconds
- Always enforce retention cap (500 items/2GB)
- No steep memory/CPU increase during long sessions

### Explicit Assumptions/Defaults
1. v1 provides English UI only.
2. Keep immediate paste as default, with restore-only fallback when permission is missing.
3. Pin UI/interactions are not provided in v1.
4. Operate as a single public distribution track.
5. App bundle ID/team ID/appcast URL are injected through release environment variables/build settings.
