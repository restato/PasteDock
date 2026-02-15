# PasteDock Features

## 1. 제품 개요

`PasteDock`는 macOS 14+ 메뉴바 클립보드 매니저 데모 앱입니다.  
핵심 목표는 최근 복사 이력을 안정적으로 저장하고, 퀵 피커에서 빠르게 복원/붙여넣기하는 것입니다.

구성은 다음 두 레이어로 나뉩니다.

- `ClipboardCore`: 캡처/저장/복원/권한 상태/토스트 등 도메인 로직
- `PasteDock`: 메뉴바 UI, 단축키, 시스템 클립보드 I/O, 런타임 운영 로직

## 2. 캡처 파이프라인

클립보드는 `NSPasteboard.changeCount`를 주기적으로 감시합니다.

- 기본 폴링 간격: `250ms` (`Settings.monitoringIntervalMs`)
- 실제 최소 간격: `50ms` (서비스 내부 보정)

캡처 순서는 아래 우선순위를 따릅니다.

1. 파일 (`NSPasteboard` 파일 URL)
2. 텍스트 (`.string`)
3. 이미지 (`.png` 또는 `.tiff` -> PNG 변환)

캡처 입력은 `CapturePipeline`으로 전달되며, 다음 정책이 적용됩니다.

- 제외 앱 스킵: `Settings.excludedBundleIds`
- 민감정보 스킵: `Settings.privacyFilterEnabled`가 켜진 경우 패턴 검사
- 연속 중복 스킵: 마지막 저장 항목의 `contentHash`와 동일하면 저장하지 않음
- 입력 검증 실패 처리:
  - 빈 텍스트
  - 빈 이미지 바이트
  - 비어 있는 파일 목록

저장 성공 후에는 용량/개수 제한 정책을 즉시 집행합니다.

- 기본 제한: `maxItems=500`, `maxBytes=2GB`
- 제한 초과 시: 오래된 항목부터 순서대로 삭제

## 3. 저장소와 페이로드

기록 저장소는 기본적으로 `GRDBHistoryStore`(SQLite)를 사용하며, 실패 시 `InMemoryHistoryStore`로 폴백합니다.

- DB: `history.sqlite`
- 텍스트 페이로드: `texts/<uuid>.txt`
- 이미지 페이로드: `images/<uuid>.png`
- 파일 페이로드: `files/<uuid>.json` (`FileClipboardPayload.paths`)

`ClipboardItem`에 저장되는 주요 메타데이터:

- `id`, `createdAt`
- `kind` (`text`, `image`, `file`)
- `previewText`
- `contentHash`
- `byteSize`
- `sourceBundleId`
- `payloadPath`

검색 동작:

- 쿼리 공백: 최신순 반환
- 쿼리 입력: `previewText` 소문자 포함 검색
- `Settings.quickPickerResultLimit`은 `maxItems`와 동기화되어 동작

## 4. 퀵 피커 및 입력 UX

메뉴바 패널은 `Quick` / `Settings` 탭으로 구성됩니다.

퀵 피커의 핵심 동작:

- 목록 초기 선택 자동 설정
- 검색어 변경 시 즉시 재조회
- 키보드 조작:
  - 숫자 입력: 인덱스 선택(다자리 입력 버퍼 지원)
  - `Enter`: 선택 항목 또는 최상단 항목 실행
  - `↑` / `↓`: 선택 이동
  - `Cmd+Backspace`: 선택 항목 삭제
  - `Esc`: 패널 닫기
- 마우스 조작:
  - 좌클릭: 즉시 실행(복원/붙여넣기)
  - 우클릭 또는 `Ctrl+클릭`: 선택만 수행(실행 없음)
- 우측 Preview 패널은 `text` / `image` / `file` 모두 지원
- Preview 대상 규칙: `hover` 우선, hover가 없으면 현재 선택 항목
- 파일 Preview: 목록 + 선택 파일 메타 + `Reveal` / `Copy Path` 액션
- 항목 컬럼: `Source`(앱명) / `Time`(`절대 시각 · 상대 시간`)

## 4.1 메뉴바 아이콘

메뉴바(status bar) 아이콘은 번들 리소스 `menuBarTemplate.png`를 사용합니다.

- 아이콘 성격: 단색 템플릿(`isTemplate = true`)
- 생성 원본: `assets/icon/source.png`
- 생성 스크립트: `bash scripts/generate-app-icon.sh`
- 리소스 누락 시: SF Symbol 아이콘으로 폴백

## 5. 복원 및 자동 붙여넣기

`PasteActionService`는 `restore`와 `restoreAndPaste` 두 경로를 제공합니다.

공통 복원:

- 텍스트: payload 파일을 읽어 pasteboard에 문자열 기록
- 이미지: PNG 읽기 후 `NSImage` 또는 raw PNG로 기록
- 파일: payload JSON의 파일 경로를 pasteboard URL 목록으로 기록

파일 복원 시 원본 파일이 없으면 실패 처리:

- 실패 사유: `file_missing`
- 사용자 메시지: `Restore failed (file missing)`

자동 붙여넣기(`Cmd+V` 이벤트 주입):

- 접근성 권한이 있으면 대상 앱 활성화 후 이벤트 전송
- 권한이 없으면 `Restored only (permission needed)` 폴백
- 자동 붙여넣기 실패 시 `Restored only`로 폴백

## 6. 권한/설정 점검(Setup Check)

`PermissionHealthService`가 아래 항목 상태를 평가합니다.

1. Accessibility
2. Login Item
3. Sparkle Update Channel

각 항목은 `ready` 또는 `actionRequired` 상태를 갖고, 필요 시 시스템 설정 이동 액션을 제공합니다.

접근성 진단 데이터:

- `isTrusted`
- `bundleId`
- `appPath`
- `isBundled`
- `guidanceReason`

권한 실패 알림 배너 정책:

- 동일 실패 사유 3회 연속 발생 시 배너 노출
- 성공 시 카운트 리셋
- `Settings.permissionReminderEnabled == false`면 비활성

## 7. 사용자 피드백/로그

토스트(`OperationToastService`)는 FIFO 큐로 관리됩니다.

- 성공/정보/경고/에러 스타일
- `Settings.showOperationToasts == false`면 토스트 미출력

로컬 로그(`LocalLogService`)는 JSONL 형식으로 기록됩니다.

- 이벤트: `capture`, `retention` 등
- 결과: `saved`, `skipped`, `failed`, `trimmed`
- 회전 정책 및 백업 파일 관리 포함

런타임 로그 파일(앱 레이어):

- `~/Library/Application Support/com-justdoit-pastedock/logs/runtime.log`

## 8. 기본 설정값

`Settings` 기본값:

- `maxItems = 500`
- `maxBytes = 2 * 1024 * 1024 * 1024`
- `quickPickerShortcut = "Cmd+Shift+V"`
- `autoPasteEnabled = true`
- `launchAtLogin = true`
- `privacyFilterEnabled = true`
- `showOperationToasts = true`
- `permissionReminderEnabled = true`
- `monitoringIntervalMs = 250`
- `quickPickerResultLimit = maxItems` (기본 500)

## 9. 현재 범위 제약

- 지원 플랫폼: macOS 14+
- 배포 대상 앱은 메뉴바 중심 데모 앱
- 외부 텔레메트리/클라우드 동기화는 현재 범위에 없음
- 배포 자동화는 Developer ID + Notary 기반 웹 배포 흐름을 기준으로 함
