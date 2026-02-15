# macOS Clipboard Manager (Swift Package)

이 저장소는 `ClipboardCore` 도메인 로직과 메뉴바 데모 앱(`PasteDock`)을 함께 제공합니다.  
배포는 App Store 없이 `Developer ID + Notary` 기반 DMG 웹 배포를 기본 경로로 사용합니다.

## 문서

- 기능 정리: `docs/features.md`
- 배포 운영 가이드: `docs/deployment.md`
- 제품/아키텍처 배경: `docs/PRD.md`
- UI 시안: `docs/ascii-ui-preview.md`

## 빠른 시작

앱 실행:

```bash
bash scripts/dev-run.sh --rebuild
```

테스트 실행:

```bash
swift test
```

직접 실행:

```bash
swift run PasteDock
```

## 개발 루프

```bash
bash scripts/dev-run.sh
bash scripts/dev-run.sh --rebuild
bash scripts/dev-tail-log.sh
bash scripts/dev-stop.sh
bash scripts/dev-diagnose-accessibility.sh
```

보조 스크립트:

```bash
bash scripts/open-accessibility.sh
bash scripts/reveal-dev-app.sh
```

런타임 로그:

```bash
~/Library/Application Support/com-justdoit-pastedock/logs/runtime.log
```

## 앱 아이콘

```bash
bash scripts/generate-app-icon.sh
```

- 입력 원본: `assets/icon/source.png`
- 결과물:
  - `assets/icon/AppIcon.iconset/*`
  - `assets/icon/AppIcon.icns`
  - `assets/icon/menuBarTemplate.png`
- `dev-run.sh`, `package-demo-dmg.sh`, `release-macos-spm.sh`에서 자동 사용

## 데모 빌드/패키징

데모 바이너리:

```bash
bash scripts/build-demo-binary.sh release
```

반복 바이너리 빌드:

```bash
bash scripts/repeat-build-demo.sh 3 release
```

데모 DMG(노타라이즈 없음):

```bash
bash scripts/package-demo-dmg.sh release
```

## 정식 릴리즈 (권장: SPM 파이프라인)

1) 환경 템플릿 복사/수정:

```bash
cp scripts/.env.release.example .env.release
```

2) 환경 로드:

```bash
set -a
source .env.release
set +a
```

3) 서명 + 노타라이즈 + 스테이플 + 체크섬:

```bash
bash scripts/release-macos-spm.sh release --tag "$RELEASE_TAG"
```

4) GitHub Release 생성 + 에셋 업로드:

```bash
bash scripts/publish-github-release.sh --tag "$RELEASE_TAG"
```

주요 결과물:

- `build/<AppName>-release/<run-id>-<config>/<AppName>-vX.Y.Z.dmg`
- `build/<AppName>-release/<run-id>-<config>/<AppName>-vX.Y.Z.dmg.sha256`
- `build/<AppName>-release/<run-id>-<config>/metadata.txt`

## Legacy 릴리즈 경로 (Xcode 프로젝트용)

`scripts/release-macos-web.sh`는 `xcodebuild archive/export` 기반 자동화 스크립트입니다.  
현재 Swift Package 기본 흐름은 `scripts/release-macos-spm.sh`를 사용합니다.

## Accessibility 트러블슈팅 요약

- 권한 목록에 앱이 없으면 `bash scripts/reveal-dev-app.sh`로 실제 번들 위치를 열어 수동 추가
- 권한이 계속 풀리면 `bash scripts/dev-diagnose-accessibility.sh`로 서명 상태 확인
- `Restored only (permission needed)`가 반복되면 접근성 권한 재허용 후 `Re-check` 실행
