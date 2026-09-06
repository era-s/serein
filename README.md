# Serein

시간표를 매일 보고 싶은 Mac 배경화면으로. **이미지·직접 입력·캘린더 → 확인·수정 → 결정론적 렌더링 → PNG 저장 / 배경화면 적용**으로 이어지는 네이티브 macOS 앱입니다.

![Serein native app](artifacts/studio.png)

## 실행

macOS 14 이상, Swift 5.10 이상이 필요합니다. 외부 패키지나 API 키 없이 Apple의 기본 프레임워크만 사용합니다.

```sh
./scripts/build-app.sh
open dist/Serein.app
```

생성된 `Serein.app`을 응용 프로그램 폴더로 옮겨 사용할 수도 있습니다. 현재 빌드는 이 Mac에서 사용할 수 있도록 ad-hoc 서명한 개발 빌드이며, Apple 공증된 배포판은 아닙니다.

## 사용법

1. 왼쪽 **시간표 이미지 가져오기**를 누르거나 PNG/JPG/HEIC 이미지를 끌어다 놓습니다. **추가**로 직접 입력할 수도 있습니다.
2. 인식 결과와 원본을 비교하고 과목을 클릭해 이름·요일·시작/종료 시간·장소를 수정합니다. 원본 이미지는 슬라이더로 최대 3배 확대할 수 있습니다. 확인 체크 후 선택한 일정을 반영합니다.
3. **디자인**에서 Ember, Moss, Midnight 테마와 문구, 학기 제목, 장소 표시, 주말, 텍스처를 설정합니다.
4. MacBook 해상도를 선택하고 **PNG 저장** 또는 **배경화면으로 설정**을 누릅니다. 적용 대상은 앱 창이 있는 디스플레이입니다.

일정은 클릭해서 수정하고 편집창의 삭제 또는 우클릭 메뉴로 삭제합니다. 겹치는 일정은 같은 칸 안에 나란히 배치됩니다. 시간 범위와 주말은 입력 일정에 맞춰 자동 확장됩니다. 데스크탑 미리보기의 메뉴 막대와 Dock은 미리보기에만 표시됩니다.

## Apple Calendar · Google Calendar

왼쪽 **캘린더에서 가져오기**(⌘K)에서 연결합니다. macOS에 등록된 캘린더를 EventKit으로 읽으며, 별도 Google API 키나 앱 내 OAuth 설정이 필요하지 않습니다.

1. **캘린더 연결**을 누르고 macOS 접근 요청을 허용합니다. 일정을 읽으려면 macOS가 ‘전체 접근’ 권한을 요청하지만, Serein은 일정을 읽기만 하며 원본을 변경하지 않습니다.
2. 사용할 캘린더를 선택하고 기준 날짜를 고릅니다. 가져오는 범위는 표시된 시간대의 월요일부터 일요일까지입니다.
3. **이 주의 일정 가져오기**를 누르고, 가져온 과목의 이름·요일·시간·장소를 검토합니다.
4. 선택한 일정을 반영하고 PNG로 저장하거나 배경화면으로 설정합니다. 선택한 주의 날짜를 배경화면 제목에 표시할 수 있습니다.

**Google 계정이 목록에 없으면:** 시스템 설정 → 인터넷 계정 → Google에서 로그인하고 **캘린더**를 켭니다. Apple 캘린더 앱에 일정이 나타난 뒤 Serein의 목록 새로고침을 누릅니다. [Google 공식 Mac 연결 안내](https://support.google.com/calendar/answer/99358?co=GENIE.Platform%3DDesktop&hl=ko)를 참고하세요. iCloud 계정도 Mac에서 캘린더 동기화가 켜져 있어야 합니다.

- 반복 일정은 선택한 주의 실제 회차로 가져옵니다. 자정을 넘는 일정은 날짜별로 나눕니다. 종일 일정·취소·참석 거절 등 제외 항목의 개수를 안내합니다.
- ‘기존 시간표를 이 일정으로 교체’를 끄면 기존 시간표에 병합합니다. 같은 출처의 일정은 갱신하므로 동일 일정을 다시 가져와도 중복되지 않습니다. 원본에서 삭제되거나 다른 날짜로 이동한 일정까지 기존 시간표에 맞추려면 **교체**를 사용하세요.
- 가져오기는 해당 주의 복사본입니다. 클라우드 동기화는 macOS 계정 설정을 따르며, 배경화면을 자동으로 갱신하지 않습니다. 캘린더 변경 후 다시 가져와 반영합니다.
- 권한 거절·계정 제거·주간 범위 변경 시 결과를 무효화합니다. 다시 반영하기 전 권한과 선택한 캘린더의 존재를 확인합니다.

## 동작과 한계

- 배경화면은 AppKit/Core Graphics의 도형, 그라데이션, 글자, 고정 패턴으로 그립니다. 같은 입력·설정·해상도와 같은 macOS/폰트 환경에서는 같은 PNG 바이트를 출력합니다. 생성형 이미지 모델은 사용하지 않습니다.
- OCR은 [Apple Vision](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)으로 기기에서 처리합니다. 이미지와 시간표를 서버에 업로드하지 않습니다.
- 명시된 요일·시간 행과 요일 열/시간축이 있는 격자형 시간표를 지원합니다. 격자 안에 수업 시간이 없으면 글자 위치를 이용해 시작 시간을 30분 단위로, 수업 길이를 기본 1시간으로 추정하므로 반드시 확인해야 합니다. 복잡한 표, 교시만 있는 표, 흐린 사진은 직접 수정하거나 추가해야 할 수 있습니다.
- 배경화면 적용은 [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace/setdesktopimageurl(_:for:options:))를 사용합니다. macOS의 현재 디스플레이/Space 동작을 따르며, 모든 가상 데스크탑을 일괄 변경하지는 않습니다.
- 작업은 `~/Library/Application Support/Serein/studio.json`에 자동 저장합니다. 적용한 PNG는 같은 디렉터리의 `Wallpapers`에 보존합니다. 손상된 작업 파일은 별도의 recovery 파일로 보관한 후 새 작업을 저장합니다.

## 검증과 예시 생성

Command Line Tools만 설치된 Mac에서도 실행할 수 있는 검증 스크립트입니다.

```sh
./scripts/verify-renderer.sh
./scripts/verify-ocr.sh
./scripts/verify-calendar.sh
```

Xcode의 XCTest가 설치된 환경에서는 `swift test`로 동일 영역의 유닛 테스트도 실행할 수 있습니다. Command Line Tools만 있는 환경은 XCTest 모듈이 없을 수 있습니다.

```sh
dist/Serein.app/Contents/MacOS/Serein --render-demo artifacts
```

캘린더 연결 화면을 개인 일정 접근 없이 확인하려면 실행 중인 Serein을 종료한 뒤 `open dist/Serein.app --args --calendar-demo`로 실행합니다. 명시적으로 예시 배지를 표시하고, 실제 계정을 읽거나 저장된 시간표를 덮어쓰지 않습니다. 일반 실행은 실제 연결 화면을 제공합니다.

- [Ember](artifacts/serein-ember.png) · [Moss](artifacts/serein-moss.png) · [Midnight](artifacts/serein-midnight.png)
- [실제 OCR 검증 이미지](artifacts/ocr-fixture.png) · [인식 결과](artifacts/ocr-fixture.txt)
- [OCR 검토 화면](artifacts/ocr-review.png) · [앱에서 직접 저장한 OCR 결과 배경화면](artifacts/ocr-import-wallpaper.png)

## 프롬프트와 결과 이력

[prompt-ledger 스킬](.agents/skills/prompt-ledger/SKILL.md)을 적용합니다. 원문과 실제 개발 결과를 분리하고, 마일스톤 커밋마다 `Prompt-ID`를 기록합니다.

| 프롬프트 | 요청 | 결과 기록 |
| --- | --- | --- |
| [P001](docs/prompts/P001.md) | 시간표 이미지/직접 입력 → 코드로 디자인한 Mac 배경화면 | [개발 기록](docs/devlog.md) |
| [P002](docs/prompts/P002.md) | 비공개 GitHub와 프롬프트별 결과 추적 | [개발 기록](docs/devlog.md) |
| [P003](docs/prompts/P003.md) | Google Calendar·Apple 캘린더의 주간 일정으로 배경화면 생성 | [개발 기록](docs/devlog.md) |

```sh
git log --all --extended-regexp --grep='^Prompt-ID: P001$' --format='%h %s'
```

선택한 커밋을 열면 그 시점의 코드, 검증 기록, 결과 이미지를 함께 볼 수 있습니다. 입력한 개인 시간표와 원본 레퍼런스 이미지는 저장소에 포함하지 않습니다.
