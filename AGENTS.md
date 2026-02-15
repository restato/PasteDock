# Repository Guidelines

## Project Structure & Module Organization
- `Sources/ClipboardCore/`: main Swift module (`Models/`, `Protocols/`, `Services/`, `QuickPicker/`, `Setup/`).
- `Tests/ClipboardCoreTests/`: unit and behavior tests using Swift Testing (`@Test`, `#expect`).
- `scripts/`: automation scripts, including `release-macos-web.sh` for signed/notarized DMG release flow.
- `packaging/ExportOptions.plist`: export settings used by macOS release automation.
- `docs/PRD.md`: product and architecture decisions that inform implementation.

## Build, Test, and Development Commands
- `swift build`: compile the `ClipboardCore` package for local validation.
- `swift test`: run all tests in `Tests/ClipboardCoreTests`.
- `swift test --filter CapturePipelineTests`: run a focused subset during iteration.
- `swift package clean`: clear build artifacts when diagnosing stale build issues.
- `bash scripts/release-macos-web.sh`: execute macOS web release pipeline (requires `.env.release` values loaded).

## Coding Style & Naming Conventions
- Swift toolchain: 6.2 (`Package.swift`), target macOS 14+.
- Use 4-space indentation and keep one primary type per file where practical.
- Type/protocol names use `UpperCamelCase`; methods/properties use `lowerCamelCase`.
- Keep service and policy names descriptive (`CapturePipeline`, `PrivacyPolicyChecking`), and prefer explicit dependency injection in initializers.
- Keep models value-oriented (`struct`) unless reference semantics are required.

## Testing Guidelines
- Framework: Swift Testing (`import Testing`) with `@Test` functions and `#expect` assertions.
- Test file names should mirror behavior under test, ending in `Tests.swift` (example: `CapturePipelineTests.swift`).
- Prefer deterministic tests with local doubles from `Tests/ClipboardCoreTests/TestDoubles.swift`.
- Cover happy paths, skip/failure branches, and async flows for services.

## Commit & Pull Request Guidelines
- Git history metadata is not available in this workspace snapshot; follow Conventional Commits (`feat:`, `fix:`, `test:`, `chore:`) until a repo-specific pattern is documented.
- Keep commits scoped to a single logical change.
- PRs should include: purpose, key changes, test evidence (`swift test` output summary), and linked issue/ticket.
- For release-impacting changes, mention updates to `scripts/` or `packaging/` and any notarization/signing implications.

## Security & Configuration Tips
- Do not commit `.env.release` or signing credentials.
- Store notarization credentials with `xcrun notarytool store-credentials` and reference via `NOTARY_PROFILE`.
- Verify required release environment variables before running release automation.
