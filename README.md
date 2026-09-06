# Serein

시간표를 매일 보고 싶은 Mac 배경화면으로. **이미지 인식 → 확인·수정 → 결정론적 렌더링 → PNG 저장 / 배경화면 적용**으로 이어지는 네이티브 macOS 앱입니다.

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
```

Xcode의 XCTest가 설치된 환경에서는 `swift test`로 동일 영역의 유닛 테스트도 실행할 수 있습니다. Command Line Tools만 있는 환경은 XCTest 모듈이 없을 수 있습니다.

```sh
dist/Serein.app/Contents/MacOS/Serein --render-demo artifacts
```

- [Ember](artifacts/serein-ember.png) · [Moss](artifacts/serein-moss.png) · [Midnight](artifacts/serein-midnight.png)
- [실제 OCR 검증 이미지](artifacts/ocr-fixture.png) · [인식 결과](artifacts/ocr-fixture.txt)
- [OCR 검토 화면](artifacts/ocr-review.png) · [앱에서 직접 저장한 OCR 결과 배경화면](artifacts/ocr-import-wallpaper.png)

## 프롬프트와 결과 이력

[prompt-ledger 스킬](.agents/skills/prompt-ledger/SKILL.md)을 적용합니다. 원문과 실제 개발 결과를 분리하고, 마일스톤 커밋마다 `Prompt-ID`를 기록합니다.

| 프롬프트 | 요청 | 결과 기록 |
| --- | --- | --- |
| [P001](docs/prompts/P001.md) | 시간표 이미지/직접 입력 → 코드로 디자인한 Mac 배경화면 | [개발 기록](docs/devlog.md) |
| [P002](docs/prompts/P002.md) | 비공개 GitHub와 프롬프트별 결과 추적 | [개발 기록](docs/devlog.md) |

```sh
git log --all --extended-regexp --grep='^Prompt-ID: P001$' --format='%h %s'
```

선택한 커밋을 열면 그 시점의 코드, 검증 기록, 결과 이미지를 함께 볼 수 있습니다. 입력한 개인 시간표와 원본 레퍼런스 이미지는 저장소에 포함하지 않습니다.
