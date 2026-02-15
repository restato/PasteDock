# Deployment Guide (SPM + Developer ID + Notarization)

## 1. 목표 산출물

릴리즈 완료 기준:

1. 서명된 `.app` 번들
2. 서명 + 노타라이즈 + 스테이플된 `.dmg`
3. `.dmg.sha256` 체크섬
4. `metadata.txt` (릴리즈 메타데이터)
5. GitHub Release 업로드 완료

기본 산출물 위치:

- `build/<AppName>-release/<run-id>-<config>/`

최신 산출물 포인터:

- `build/latest-release-dir.txt`

## 2. 사전 준비

필수 준비물:

1. Apple Developer Program 계정
2. 로그인 키체인에 `Developer ID Application` 인증서 설치
3. `xcrun notarytool store-credentials`로 notary profile 저장
4. `gh auth login` 완료(GitHub Releases 업로드용)
5. `.env.release` 파일 준비(`scripts/.env.release.example` 기반)

필수 명령:

- `swift`
- `codesign`
- `xcrun`
- `hdiutil`
- `spctl`
- `gh`
- `git`

## 3. 환경 변수 설정

```bash
cp scripts/.env.release.example .env.release
```

필수 변수:

- `DEVELOPER_ID_APP`
- `NOTARY_PROFILE`
- `RELEASE_TAG` (`vX.Y.Z`)
- `GITHUB_REPOSITORY` (`owner/repo`)

권장 변수:

- `APP_NAME`
- `APP_TARGET`
- `BUNDLE_ID`
- `MIN_MACOS_VERSION`
- `GH_RELEASE_NOTES_FILE`

환경 로드:

```bash
set -a
source .env.release
set +a
```

## 4. 릴리즈 실행 절차

### Step 1) 아이콘 생성

```bash
bash scripts/generate-app-icon.sh
```

확인 파일:

- `assets/icon/AppIcon.icns`
- `assets/icon/menuBarTemplate.png`

### Step 2) 패키지 테스트

```bash
swift test
```

### Step 3) 로컬 릴리즈 빌드 + 서명 + 노타라이즈

```bash
bash scripts/release-macos-spm.sh release --tag "$RELEASE_TAG"
```

옵션:

- `--skip-notarize`: 서명/패키징까지만 수행할 때 사용
- `debug`: 디버그 구성으로 패키징할 때 사용

### Step 4) GitHub Release 생성 및 에셋 업로드

```bash
bash scripts/publish-github-release.sh --tag "$RELEASE_TAG"
```

선택 옵션:

- `--artifact-dir <dir>`: 업로드할 산출물 디렉터리 명시
- `--notes <file>`: 릴리즈 노트 파일 명시
- `--repo owner/repo`: 저장소 명시

## 5. 검증 체크리스트

앱 서명 검증:

```bash
codesign --verify --deep --strict --verbose=2 "<path>/<AppName>.app"
spctl -a -t exec -vv "<path>/<AppName>.app"
```

DMG 검증:

```bash
codesign --verify --verbose=2 "<path>/<AppName>-vX.Y.Z.dmg"
spctl -a -t open --context context:primary-signature -vv "<path>/<AppName>-vX.Y.Z.dmg"
xcrun stapler validate "<path>/<AppName>-vX.Y.Z.dmg"
```

체크섬 검증:

```bash
shasum -a 256 -c "<path>/<AppName>-vX.Y.Z.dmg.sha256"
```

## 6. 장애 대응 런북

### 6.1 인증서 관련 실패

증상:

- `codesign` 실패
- 인증서 찾기 실패

대응:

1. Keychain Access에서 `Developer ID Application` 인증서 존재 확인
2. `.env.release`의 `DEVELOPER_ID_APP` 값이 정확한지 확인
3. 필요 시 `security find-identity -v -p codesigning`로 식별자 재확인

### 6.2 노타라이즈 실패

증상:

- `notarytool submit` 실패
- 스테이플 실패

대응:

1. `NOTARY_PROFILE` 이름 재검증
2. notary profile 재생성
3. 스크립트 출력된 notary 로그/요약 확인 후 재실행

### 6.3 GitHub 업로드 실패

증상:

- `gh release create` 또는 `gh release upload` 실패

대응:

1. `gh auth status` 확인
2. `GITHUB_REPOSITORY` 값 확인
3. 태그 푸시 권한 확인

## 7. 버전 정책

버전 단일 소스는 `Git 태그(vX.Y.Z)`입니다.

- `CFBundleShortVersionString`: `v`를 제거한 `X.Y.Z`
- `CFBundleVersion`: `X.Y.Z.<commit-count>` (기본)
- 릴리즈 파일명: `<AppName>-vX.Y.Z.dmg`

## 8. Legacy 경로

`scripts/release-macos-web.sh`는 Xcode 프로젝트/워크스페이스 기반 릴리즈 흐름입니다.  
현재 저장소의 기본 릴리즈 경로는 `scripts/release-macos-spm.sh`입니다.
