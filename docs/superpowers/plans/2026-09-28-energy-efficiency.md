# 추가 전력 최적화 실행 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 캘린더 정확성과 이미지 품질을 유지하면서 중복 조회·저장·보이지 않는 미리보기 작업을 줄인다.

**Architecture:** 기존 알림 기반 자동화와 단일 작업자를 유지한다. 변경 원인을 구분해 필요한 처리만 실행하고, 입력 저장과 창 가시성을 별도로 관리한다. 캐시와 스레드 구조 변경은 측정에서 비용이 확인될 때만 추가한다.

**Tech Stack:** Swift, SwiftUI, AppKit, EventKit, Combine, Core Graphics, SwiftPM.

**Spec:** [P013](../../prompts/P013.md), [승인된 P012 동작](../../prompts/P012.md), 아래 검토 결과와 동작 계약.

**상태:** [P014](../../prompts/P014.md) 승인에 따라 사유별 조회, 저장 묶기, 창 가시성 처리를 구현했다. 기준 구현: `3026a33` / 앱 0.3.7(11). 결과와 실제 실행한 검사는 [M019](../../devlog.md#m019--추가-전력-최적화와-배경화면-정리--2026-09-28)에 기록한다. 아래 장시간 전력 A/B 프로토콜은 실행하지 않았으며 미완료 항목은 그대로 남긴다.

## Global Constraints

- macOS 14 이상, 추가 외부 패키지 없이 구현한다.
- 창 닫기는 메뉴 막대 상주, 다시 열기는 Dock 복원, ⌘Q는 완전 종료로 유지한다.
- 이번 주 범위, 매주 교체 옵션, 오늘 표시, 숨긴 반복 일정, 수동 일정 보존을 유지한다.
- 생성형 AI 없이 결정론적으로 렌더링하며 최종 PNG 해상도를 유지한다. P014의 추가 요청에 따라 고정 장식 문구 5개와 구형 도형만 제거한다.
- 원본 캘린더에는 쓰지 않고, 개인 일정·계정 식별자·실제 화면·프로파일 원본을 공개하지 않는다.
- 전체 Space 적용의 원본 백업·동시 변경 검사·적용 검증·실패 복구를 생략하지 않는다.
- 배터리/저전력 모드 때문에 일정 반영을 임의로 몇 분씩 늦추지 않는다.
- P014가 구현을 승인했다. 공개 결과에는 가상 일정만 사용한다.

## 검토 결과

이전 변경에서 60초 타이머, 닫힌 창의 미리보기, 동일 입력 재렌더링은 이미 제거했다. 기존 70초 유휴 관찰의 CPU 시간 증가 0.12초는 짧은 관찰치일 뿐 전력량·배터리 절감률을 입증하지 않는다. 따라서 다음 단계는 유휴 CPU 수치만 더 낮추기보다 사용 중·동기화 중의 불필요한 작업을 줄이는 데 집중한다.

| 순서 | 확인한 코드 동작 | 제안 | 기대 효과 / 주의점 |
|---|---|---|---|
| 1 | `WallpaperAutomation.swift:126–128`: 일정 변경 자동화가 켜진 현재 주는 트리거와 무관하게 조회 | 디자인 변경과 실제 캘린더 갱신 사유 구분 | 디자인 편집·반복 활성화의 불필요한 EventKit 조회/변환 감소. 병합 중 변경 누락 위험이 핵심 |
| 2 | `AppStore.swift:117–127`, `StudioView.swift:287–299`: 제목 바인딩 변경마다 전체 JSON 즉시 저장 | 텍스트 연속 입력 저장을 짧게 합치고 닫기/종료 시 저장 완료 | 편집 중 디스크 쓰기 감소. 강제 종료 시 지연 구간의 입력 유실 가능성을 검토 |
| 3 | `StudioWindowLifecycle.swift:28–37`: 닫기와 키 창 전환만 관찰 | 최소화·앱 숨김·완전 가림도 미리보기 중단 | 보이지 않는 창의 자동 갱신 렌더 제거. 배경화면 적용은 계속 |
| 4 | `WallpaperRenderer.swift:416–437`: 매 렌더마다 동일 규칙의 종이 질감 버퍼 생성 | 비용이 확인되면 마지막 크기 1개의 CGImage만 재사용 | 렌더당 CPU 감소 후보. 항상 유지할 메모리와 비교 필요 |
| 5 | `CalendarAccessRecovery.swift:20–22` 및 AppStore 알림: 같은 상태도 게시 | 동일 값 대입·중복 상태 게시 생략 | SwiftUI 재평가 감소 후보. 앞 단계와 함께 작은 수정으로 처리 |

1–3의 구조적 중복은 코드로 확인했다. 전력 절감의 크기와 4–5의 우선순위는 측정 전 가설이다. 닫힌 상태에서 이미 유휴라면 추가 절감은 작을 수 있다.

## Task 1: 비교 가능한 측정 기준 만들기

**Files:** 새 `scripts/verify-energy-behavior.swift`, `scripts/verify-energy-behavior.sh`; 필요할 때만 `Sources/TimetableWallpaper/AppStore.swift`와 `WallpaperAutomation.swift`에 기본 꺼짐 signpost 추가. 결과 요약은 `artifacts/energy-comparison.json`.

**Interfaces:** 합성 provider와 임시 저장 목적지를 사용하는 실행 하네스. 공개 결과에는 횟수·소요 시간·바이트·OS/앱 버전만 담는다. EventKit 조회, 미리보기, PNG 인코딩, 저장, wallpaper apply 경계별 횟수를 측정한다. 테스트용 가짜 객체는 파일 시스템·캘린더·벽지 적용 경계에만 둔다.

- [ ] 기존 0.3.7 Release를 기준으로 같은 Mac·전원·밝기·화면 구성·합성 일정에서 측정한다. 디버거를 떼고 유휴 측정하며 첫 실행 준비 시간은 제외한다.
- [ ] 닫힌 상태, 창이 보이는 상태, 최소화 상태를 각각 10분씩 3회 관찰한다. CPU 시간, wakeups, 파일 쓰기, RSS, 사용 가능한 Xcode Instruments/Activity Monitor의 Energy Impact·App Nap을 함께 기록한다. 에너지 도구가 해당 OS에서 지원하지 않는 항목은 미측정으로 표시한다.
- [ ] 50 ms 간격 제목 20자 입력, 디자인 변경 10회, 1초 안 EventKit 알림 20회, 조회 중 추가 알림, 자정·월요일 전환, 잠자기 복귀를 합성 입력으로 재현한다. 실제 개인 캘린더를 변경하지 않는다.
- [ ] 변경 전후 3회 중앙값과 범위를 비교한다. 에너지 수치는 상대 비교로 사용하며 CPU 비율을 배터리 시간으로 환산하지 않는다.
- [ ] 아래 2–4의 완료 기준을 하네스의 실패하는 검사로 먼저 만든 뒤 해당 단계 구현을 진행한다. 항상 켜지는 진단 타이머나 파일 로그를 제품에 넣지 않는다.

**완료 기준:** 외부 이벤트 없는 닫힌 상태의 반복 조회·렌더·저장·적용은 각각 0회. 실제 변경 시 마지막 상태가 반영되는 횟수와 지연도 함께 측정한다. 이 수치는 OS 프로세스 전체 wakeup 0회를 뜻하지 않는다.

## Task 2: 캘린더 조회 사유와 화면 변경 사유 분리

**Files:** `Sources/TimetableWallpaper/AutomationModels.swift`, `WallpaperAutomation.swift`, `AppStore.swift`; `scripts/verify-automation.swift`, Task 1 하네스.

**Interfaces:** `AutomationTrigger`에 활성화·디스플레이·날짜 변경의 의미를 구분한다. 예약 요청과 worker 요청에 캘린더 변경 대기 상태를 보존하며, 연결 ID/선택 범위가 다른 요청에 오래된 결과를 섞지 않는다. `WallpaperAutomation.check`의 단일 worker·generation 검증은 유지한다.

현재 예약기와 worker는 `.settingsChanged`가 `.calendarChanged`보다 우선한다. 조회 조건만 트리거별로 좁히면 편집 도중 도착한 실제 캘린더 변경을 잃는다. 이 병합 규칙을 먼저 수정해야 한다.

**동작 계약:**

```text
pendingCalendarDirty = pendingCalendarDirty OR incomingCalendarChanged
fetch = explicitEnableOrReconnect OR manualCheck OR launchOrRealWake
        OR calendarDirty OR permissionRecovered
        OR (weeklyEnabled AND weekChanged)
appearanceOnly = designEdited OR displayChanged OR ordinaryActivation OR dayChanged
```

이 식은 사유 분리 계약이다. 현재 코드의 자동화 옵션, 연결 유무, 주 변경 허용 여부를 먼저 적용한다. 날짜 변경과 실제 시스템 시각/시간대 변경은 구분하고, 시간대 변경에는 현재 주 범위를 다시 계산한다. 디자인 변경만으로 숨김 복원이 필요한 경우와 연결 변경을 혼동하지 않도록 숨김 해제·재연결은 명시적 조회 사유로 보존한다.

- [x] 기존 요청 횟수 기록용 합성 provider로, 활성화/디자인/화면 변경 10회에 추가 조회가 생기는 실패 검사를 만든다. 기준 snapshot이 있고 권한·주·연결이 동일한 경우 추가 조회 목표는 0회다.
- [x] 편집 debounce 중 EventKit 변경, 실행 중 변경, 연결 변경, 숨김 해제, 권한 회복을 각각 검사한다. 단순히 마지막 트리거 이름만 저장하지 않고 필요 사유를 병합한다.
- [x] 성공한 조회만 해당 변경 대기 상태를 해소한다. 진행 중 더 새로운 알림이 왔으면 후속 조회 1회를 남긴다. 실패는 복구 필요 상태를 남기되 반복 재시도 타이머를 추가하지 않는다.
- [x] 일반 활성화는 권한 회복·직전 실패·보류 변경이 없으면 조회를 생략한다. 실제 launch/wake/수동 확인은 빠른 복구 경로로 유지한다. 알림 누락 복구를 약화시키지 않는다.
- [x] 테스트: 1초 안 20개 알림은 묶어서 1회 조회, 조회 중 변경은 마지막 상태까지 후속 조회, 주간 옵션 OFF 시 자동 주 이동 없음, 오늘만 변경 시 기존 일정으로 렌더, 권한 철회·회복과 숨긴 반복 일정 유지.
- [x] `./scripts/verify-automation.sh`, `./scripts/verify-calendar-visibility-app.sh`, `./scripts/verify-calendar-recovery.sh`와 Task 1 하네스를 실행한다. 예시 데이터 기준으로 변경 누락과 추가 PNG 적용이 없어야 한다.
- [ ] 현재 조회 1회에 캘린더 열거가 3회(사전 검증, provider 조회, 사후 검증) 발생한다. 먼저 불필요한 조회 자체를 줄인 뒤 측정하고, 열거 비용이 남으면 사전 검증은 권한·선택 유무만 확인하고 provider 내부 선택 ID 검증과 사후 재검증은 유지한다. provider 계약과 가짜 provider 시험도 함께 수정해 삭제된 캘린더·조회 중 권한 철회가 거부되는지 확인한다. 원본 EventKit 객체의 장기 캐시는 도입하지 않는다.
- [x] 숨긴 원본은 필터링 전에 식별 정보를 reconcile한다. 실제 적용 시에만 바뀌는 receipt.dayKey를 마지막 조회 시각으로 재사용하지 않는다. 시간대 변경과 실패 후 복구 상태를 독립적으로 보존한다.
- [x] 의미 없는 동일 access/login/status 대입을 비교 후 생략하되, 실제 권한 변화와 오류 해제는 게시한다. 이 미세 최적화 때문에 ObservableObject 구조 전체를 재작성하지 않는다.
- [ ] 검사 통과 후 P013·P002 트레일러로 독립 커밋한다.

## Task 3: 편집 중 저장 묶기

**Files:** `Sources/TimetableWallpaper/AppStore.swift`, `WallpaperApp.swift`, `StudioWindowLifecycle.swift`; 새 `Sources/TimetableWallpaper/StudioPersistence.swift`와 `scripts/verify-persistence.swift`, 실행 셸 하네스.

**Interfaces:** 저장소 소유자에 `schedule(_ snapshot: SavedStudio)`와 `flush() throws` 경계를 둔다. 임시 디렉터리를 주입할 수 있게 하되 개인 경로 기본값은 유지한다. AppStore 모델 변경과 저장 예약을 분리한다.

**계약:**

```text
continuous text editing -> cancel previous save -> save latest after 300 ms quiet
close / application termination / sleep -> flush pending snapshot immediately
explicit event save/delete/hide/import / automation receipt -> persist immediately
successful write -> mark saved; failed write -> retain pending and surface error
```

- [x] 50 ms 간격 20자 입력 후 저장 1회, 동일 snapshot 중복 저장 0회 검사를 먼저 작성한다. 재시작 시 마지막 입력을 읽어 실제 디스크 결과를 검증한다.
- [x] 원자적 쓰기를 유지하고, 텍스트 편집만 우선 묶는다. 입력 중 계속 타이핑해도 장시간 미저장이 되지 않도록 첫 미저장부터 최대 2초의 상한을 둔다. 반복 타이머가 아닌 대기 저장 하나로 관리한다.
- [x] 창 닫기·⌘Q·메뉴 종료·시스템 종료·잠자기 전에 flush한다. 정상 종료 전에 실패하면 저장 오류를 알리고 재시도/종료 취소가 가능해야 한다. ‘저장됨’처럼 표시하고 실패를 무시하지 않는다.
- [x] 강제 종료/전원 단절에서는 flush를 보장할 수 없다. 마지막 지연 구간의 텍스트 입력이 손실될 수 있으므로, 이 위험을 수용하지 않으면 텍스트도 즉시 저장을 유지하고 중복 snapshot만 제거하는 축소안으로 진행한다. 일정 삭제·숨김은 지연하지 않는다.
- [x] 저장 실패, 빠른 닫기·종료, 연속 편집 도중 자동화 metadata 반영, 오래된 예약이 새 snapshot을 덮지 않는 경우를 테스트한다. 모든 시험은 임시 파일로 수행한다.
- [ ] 데이터 보존 검사 통과 및 쓰기 감소 확인 후 별도 커밋한다. 저장 형식 변경이나 데이터베이스 도입은 하지 않는다.

## Task 4: 보이지 않는 미리보기까지 중단

**Files:** `Sources/TimetableWallpaper/StudioWindowLifecycle.swift`, `AppStore.swift`; Task 1 하네스, `scripts/verify-calendar-visibility-app.swift`.

**Interfaces:** 기존 `setStudioVisible(_:)`를 미리보기 실행 가능 여부로 사용한다. Dock 전환은 기존의 창 닫기/열기에서만 한다.

```text
previewAllowed = window.isVisible
                 AND !window.isMiniaturized
                 AND window.occlusionState.contains(.visible)
                 AND !NSApp.isHidden
```

- [ ] 최소화, ⌘H, 완전히 가려진 창에서 모델을 바꿔도 preview render가 0회인 검사를 만든다. 일부라도 보이는 창과 단순 비활성 창은 억제 대상으로 삼지 않는다.
- [x] AppKit의 가시성·최소화·앱 숨김 변경 알림을 관찰하고, 값이 실제로 바뀔 때만 AppStore에 전달한다. 키 창 여부를 보임 여부로 대신하지 않는다.
- [x] 재노출 시 최신 입력으로 1회만 렌더링하고, 변경 없으면 캐시를 쓴다. 장시간 숨김에 대한 주기 검사나 메모리 정리 타이머를 만들지 않는다.
- [ ] 미리보기가 숨겨져 있어도 캘린더 동기화·오늘 표시·전체 Space 배경화면 적용은 계속되는지 검증한다. 메뉴 열기, 파일 다이얼로그, 다른 Space, 여러 화면, 닫기→열기→⌘Q도 실제 앱에서 확인한다.
- [ ] Dock 정책 회귀 없이 숨긴 상태의 렌더 횟수가 0회인 경우 커밋한다.

## Task 5: 측정 결과에 따른 선택 단계

1–4 이후 새 프로파일을 보고 다음 중 실제 비용이 남은 항목만 선택한다.

- **질감 캐시:** `WallpaperRenderer.swift:416`의 생성 루프가 반복 렌더 CPU에서 의미 있는 비중이면 마지막 `(1512, height)` 질감 CGImage 1개만 보관한다. 다른 크기는 교체하고 메모리 압력에는 해제한다. 입력·시드·색 공간은 그대로 두며 3개 테마·5개 해상도의 캐시 유무 출력 픽셀 일치를 검증한다. PNG 인코딩 메타데이터 차이와 픽셀 차이를 구분한다. 측정된 시간 감소가 메모리 증가에 비해 작으면 도입하지 않는다.
- **동일 PNG 수동 재적용:** 현재는 PNG를 만든 다음 해시를 비교하므로 같은 결과도 인코딩한다. 다만 자동화에는 이미 fingerprint 차단이 있어 수동 재적용 빈도가 낮으면 가치가 작다. 수동 적용은 사용자가 바꾼 바탕화면을 다시 복원하는 의미가 있으므로 앱 receipt만 보고 적용 전체를 생략하지 않는다.
- **백그라운드 계산:** EventKit 조회·렌더·적용 대기가 main actor에 있어 응답성 개선 여지는 있지만, 스레드를 옮기는 것 자체는 에너지 절감 증거가 아니다. UI 지연이 측정된 경우에만 EventKit 객체 소유권, AppKit 렌더 thread safety, 취소·generation·완료 저장 순서를 설계해 별도 작업으로 분리한다.
- **저전력 모드:** 최종 PNG 화질이나 달력 갱신 시점을 바꾸지 않는다. 필요하면 편집 중 임시 미리보기의 빈도만 낮추는 방식을 별도 검토한다. 새 옵션·서비스·백그라운드 helper를 먼저 만들지 않는다.

## 검증과 배포 순서

측정 기준 → 사유 분리 → 저장 안전성 검증 후 묶기 → 가시성 확대 → 재측정 → 필요한 캐시만 추가.

- [ ] 위 작업의 검사와 기존 자동화·숨김·권한·렌더·전체 Space 검사를 수행한다. 각 단계에서 결과를 실제 실행한 만큼만 devlog에 적는다.
- [ ] Release 패키징, 이전 코드 서명 요구사항 일치, 개인 일정/옵션 유지, 창 닫기/재개/종료와 월요일·자정·잠자기 복구를 확인한다.
- [ ] 성능 개선은 작업 횟수·CPU 시간·에너지 도구 결과를 함께 비교한다. 0% CPU 스냅샷 하나로 완료 판정하지 않는다.
- [ ] 공개 저장소에는 가상 입력, 검증 코드와 익명 집계만 커밋한다. 실제 일정이 들어갈 수 있는 Instruments trace와 screenshots는 로컬에 남긴다.

## 판단 근거

- [Apple: App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html): OS의 절전만 기다리지 않고 보이지 않는 작업을 먼저 중단하는 방향을 채택한다.
- [Apple: Minimize I/O](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/MinimizingIO.html): 변경이 있을 때 쓰고 연속 쓰기를 묶는 방향을 채택한다.
- [Apple: EKEventStoreChanged](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/ekeventstorechanged): 변경 후 기존 EventKit 객체는 오래된 것으로 취급하고 필요한 범위를 다시 조회한다. 비공개 userInfo 키로 선택 캘린더 변경을 추측해 알림을 버리지 않는다.

검토일 2026-09-28. 위 Apple 에너지 가이드는 오래된 문서이며 원칙의 근거로 사용했다. 실제 도구 지원과 절감 효과는 현재 macOS/Xcode에서 별도로 확인한다.

### P014 실행 범위와 보류 사항

- 20회 입력·10회 디자인 변경·10회 일반 활성화·20회 캘린더 알림의 실제 작업 횟수를 합성 하네스에서 검증했다. 저장은 임시 파일에서 재로드해 마지막 입력을 확인했다. 월요일·자정·권한·조회 중 알림은 자동화 회귀 검사로 확인한다.
- 10분 × 3회 × 3상태의 변경 전후 관찰(합계 180분), Energy Impact·App Nap·wakeups·RSS의 장기 비교는 수행하지 않았다. 배터리 절감률을 주장하지 않는다.
- 질감 생성의 단독 CPU 중앙값은 최종 PNG 비용의 약 0.44–0.72%였다. 메모리 상주 비용에 비해 이득이 작아 캐시는 도입하지 않았다. PNG 재적용 캐시, 스레드 이동, 새 저전력 옵션도 추가하지 않았다.
- 캘린더 사전·사후 검증은 유지했다. 조회 횟수를 줄였으며, 원본 객체를 장기 캐시하거나 검증 단계를 생략하지 않았다.
