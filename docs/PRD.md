## macOS 클립보드 매니저 v1 최종 계획 (이전 스레드 연속, 결정 반영판)

### 요약
1. 목표: `macOS 14+` 메뉴바 앱으로 텍스트/이미지 클립보드 히스토리를 영구 저장하고, 빠른 재붙여넣기 중심 UX를 제공한다.
2. 이번에 확정된 핵심 결정:
- 퀵 피커: `Spotlight형 중앙 팝업`
- 선택 트리거: `숫자(1~9) 즉시 실행`
- `핀 UI`: v1 범위에서 제거
3. 기존 확정 유지:
- 저장 정책: 최대 500개 + 총 2GB 상한(초과 시 오래된 항목부터 삭제)
- 제외 앱: 기본 목록 + 사용자 편집
- 보호 모드: 민감 패턴 감지 시 저장 스킵
- 업데이트: v1부터 Sparkle 자동업데이트
- 언어: 영어만
- 진단: 로컬 로그만
- 출시: 바로 공개 배포
- 배포 자동화: `/Users/direcision/Workspace/just-do-it/scripts/release-macos-web.sh` 기반

### 범위
1. 포함
- 메뉴바 앱 + 설정창
- 클립보드 감시/저장(텍스트, 이미지)
- 검색, 삭제, 전체 비우기
- 글로벌 단축키 `Cmd+Shift+V`로 중앙 팝업 퀵 피커 호출
- 숫자 선택 즉시 `복원 + 자동 붙여넣기` (권한 없으면 복원-only fallback)
- 로그인 시 자동 실행
- Sparkle 업데이트
2. 제외
- iCloud/동기화, OCR, AI 분류, 협업 공유
- 외부 텔레메트리(Sentry/Crashlytics)

### 아키텍처/모듈
1. `ClipboardMonitor`: `NSPasteboard.changeCount` 감시.
2. `CapturePipeline`: 타입 판별 -> 민감정보/제외앱 검사 -> 중복 제거 -> 저장.
3. `HistoryStore`(SQLite+GRDB): CRUD/검색/정렬.
4. `RetentionManager`: 500개/2GB 정책 집행.
5. `QuickPickerController`: 중앙 팝업, 검색, 숫자 즉시 실행.
6. `PasteActionService`: `restore` 및 `restoreAndPaste`(권한 기반 분기).
7. `PrivacyPolicyService`: 제외 앱 + 민감 패턴 필터.
8. `LaunchAtLoginService`, `UpdaterService(Sparkle)`, `LocalLogService`.

### 공개 인터페이스/타입 변경
1. `ClipboardItem`
- `id`, `createdAt`, `kind(text|image)`, `previewText`, `contentHash`, `byteSize`, `sourceBundleId`, `payloadPath`
- 변경점: 핀 UI는 제거하고, 내부 데이터 구조는 호환성 위해 유지
2. `Settings`
- `maxItems`, `maxBytes`, `quickPickerShortcut`, `autoPasteEnabled`, `launchAtLogin`, `excludedBundleIds`, `privacyFilterEnabled`
3. 저장소 API
- `save(item)`, `search(query, limit)`, `delete(id)`, `clearAll()`, `enforceLimits()`
4. 액션 API
- `restore(id)`, `restoreAndPaste(id)`
- 숫자 선택 경로는 기본 `restoreAndPaste(id)` 호출, 권한 미충족 시 `restore(id)`로 자동 전환

### 데이터/정책
1. 이미지 원본은 `Application Support/<App>/images/<uuid>`에 저장, DB에는 메타데이터+경로 저장.
2. 연속 중복(`contentHash`)은 재저장하지 않음.
3. 정리 정책은 오래된 항목부터 삭제.

### 테스트 케이스/시나리오
1. 단위 테스트
- 민감 패턴 필터, 제외 앱 필터, 중복 제거, 500개/2GB 정리 로직, 검색 정렬
2. 통합 테스트
- 텍스트/이미지 캡처-복원
- 퀵 피커 호출(`Cmd+Shift+V`) 및 숫자 즉시 실행
- 접근성 권한 없음 fallback(복원-only)
- 앱 재시작 후 영속성
3. 배포/릴리즈 테스트
- Sparkle 업데이트(구버전->신버전)
- 노타라이즈 DMG 설치 및 Gatekeeper 통과
4. 인수 기준
- 과거 항목 복구/붙여넣기 2초 내
- 저장 상한(500개/2GB) 항상 준수
- 장시간 사용 시 메모리/CPU 급증 없음

### 명시적 가정/기본값
1. v1은 영어 UI만 제공.
2. 즉시 붙여넣기 기본값 유지, 권한 없으면 복원-only.
3. 핀 UI/조작 기능은 v1에서 제공하지 않음.
4. 공개 배포 단일 트랙으로 운영.
5. 앱 번들 ID/팀 ID/앱캐스트 URL은 릴리즈 환경변수/빌드 설정으로 주입.
