# Deployment Guide (SPM + Developer ID + Notarization)

## 1. Target Artifacts

Release completion criteria:

1. Signed `.app` bundle
2. Signed + notarized + stapled `.dmg`
3. `.dmg.sha256` checksum
4. Fixed `latest` filenames for `.dmg` / `.dmg.sha256`
5. `metadata.txt` (release metadata)
6. GitHub Release upload completed

Default artifact location:

- `build/<AppName>-release/<run-id>-<config>/`

Stable latest download URL:

- `https://restato.github.io/projects/pastedock/`

Latest artifact pointer:

- `build/latest-release-dir.txt`

## 2. Prerequisites

Required items:

1. Apple Developer Program account
2. `Developer ID Application` certificate installed in login keychain
3. Notary profile stored with `xcrun notarytool store-credentials`
4. `gh auth login` completed (for GitHub Releases upload)
5. `.env.release` file prepared from `scripts/.env.release.example`

Required commands:

- `swift`
- `codesign`
- `xcrun`
- `hdiutil`
- `spctl`
- `gh`
- `git`

## 3. Environment Variables

```bash
cp scripts/.env.release.example .env.release
```

Required variables:

- `DEVELOPER_ID_APP`
- `NOTARY_PROFILE`
- `RELEASE_TAG` (`vX.Y.Z`)
- `GITHUB_REPOSITORY` (`owner/repo`)

Recommended variables:

- `APP_NAME`
- `APP_TARGET`
- `BUNDLE_ID`
- `MIN_MACOS_VERSION`
- `GH_RELEASE_NOTES_FILE`

Load environment variables:

```bash
set -a
source .env.release
set +a
```

## 4. Release Execution Steps

### Step 1) Generate icons

```bash
bash scripts/generate-app-icon.sh
```

Verify files:

- `assets/icon/AppIcon.icns`
- `assets/icon/menuBarTemplate.png`

### Step 2) Run package tests

```bash
swift test
```

### Step 3) Build + sign + notarize locally

```bash
bash scripts/release-macos-spm.sh release --tag "$RELEASE_TAG"
```

Options:

- `--skip-notarize`: use when you only need signing/packaging
- `debug`: use when packaging with debug configuration

### Step 4) Create GitHub Release and upload assets

```bash
bash scripts/publish-github-release.sh --tag "$RELEASE_TAG"
```

Optional flags:

- `--artifact-dir <dir>`: specify artifact directory to upload
- `--notes <file>`: specify release notes file
- `--repo owner/repo`: specify repository

## 5. Verification Checklist

Verify app signature:

```bash
codesign --verify --deep --strict --verbose=2 "<path>/<AppName>.app"
spctl -a -t exec -vv "<path>/<AppName>.app"
```

Verify DMG:

```bash
codesign --verify --verbose=2 "<path>/<AppName>-vX.Y.Z.dmg"
spctl -a -t open --context context:primary-signature -vv "<path>/<AppName>-vX.Y.Z.dmg"
xcrun stapler validate "<path>/<AppName>-vX.Y.Z.dmg"
```

Verify checksum:

```bash
shasum -a 256 -c "<path>/<AppName>-vX.Y.Z.dmg.sha256"
```

## 6. Failure Runbook

### 6.1 Certificate-related failures

Symptoms:

- `codesign` failure
- Certificate lookup failure

Actions:

1. Confirm `Developer ID Application` certificate exists in Keychain Access
2. Confirm `DEVELOPER_ID_APP` in `.env.release` is correct
3. If needed, re-check identity with `security find-identity -v -p codesigning`

### 6.2 Notarization failures

Symptoms:

- `notarytool submit` failure
- Stapling failure

Actions:

1. Re-verify `NOTARY_PROFILE` name
2. Recreate the notary profile
3. Review the notary logs/summary printed by the script and retry

### 6.3 GitHub upload failures

Symptoms:

- `gh release create` or `gh release upload` failure

Actions:

1. Check `gh auth status`
2. Verify `GITHUB_REPOSITORY`
3. Verify tag push permissions

## 7. Version Policy

The single source of version truth is the Git tag (`vX.Y.Z`).

- `CFBundleShortVersionString`: `X.Y.Z` (without the `v`)
- `CFBundleVersion`: `X.Y.Z.<commit-count>` (default)
- Release filename: `<AppName>-vX.Y.Z.dmg`
