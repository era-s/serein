# 개발 기록

원문 프롬프트와 실제 결과를 분리해서 기록한다. 각 마일스톤을 담은 커밋이 당시 결과의 스냅샷이며, 커밋의 `Prompt-ID` 트레일러로 연결된다. 새 결과와 검증은 완료된 시점에 이 문서에 추가한다.

## M001 · 요청과 개발 기록 체계 · 2026-09-06

- 프롬프트: [P001](prompts/P001.md), [P002](prompts/P002.md)
- 결과: 원문 요청을 보존하고 [prompt-ledger 스킬](../.agents/skills/prompt-ledger/SKILL.md)과 [저장소 작업 지침](../AGENTS.md)을 추가했다. 개인 Codex 스킬로도 설치해 다른 프로젝트에서 재사용할 수 있게 했다.
- 검증: 스킬 생성기의 `quick_validate.py`로 개인 설치본과 저장소 사본을 검증했다. 두 파일의 내용이 동일함을 확인했다.

특정 프롬프트의 결과 이력은 아래 명령으로 확인한다. 선택한 커밋을 열면 그 시점의 코드, 기록, 결과물이 함께 나온다.

```sh
git log --all --extended-regexp --grep='^Prompt-ID: P001$' --format='%h %s'
git log --all --extended-regexp --grep='^Prompt-ID: P002$' --format='%h %s'
```

## M002 · 네이티브 앱과 코드 기반 배경화면 · 2026-09-06

- 프롬프트: [P001](prompts/P001.md), [P002](prompts/P002.md)
- 결과: SwiftUI 시간표 편집기, 3개 테마, 문구/해상도 설정, 자동 저장, PNG 저장과 사용자가 누르는 배경화면 적용 버튼을 연결했다. AppKit/Core Graphics 렌더러와 기기 내 Apple Vision OCR을 구현했다. 인식 결과는 원본과 비교·수정하고 확인한 뒤 반영한다.
- 결과물: [Ember](../artifacts/serein-ember.png), [Moss](../artifacts/serein-moss.png), [Midnight](../artifacts/serein-midnight.png), [실제 OCR 입력](../artifacts/ocr-fixture.png), [인식 결과](../artifacts/ocr-fixture.txt).
- 검증: release 빌드와 `Serein.app` 패키징/서명 성공. 렌더러 검증 14개 통과(같은 입력의 PNG 바이트 일치, 출력 해상도, 빈 시간표, 주말/자정 경계, 일정 겹침 등). OCR 검증 47개 통과(파서/오류 40개, 실제 Apple Vision 이미지 인식 7개).
- 시각 검토: 3개 테마와 짧은 수업/겹치는 한글 제목을 확인했다. 검토 과정에서 30분 일정의 제목 누락과 긴 제목 줄바꿈을 수정했다. 저장 파일 오류 시 원본 복구본을 보존하도록 수정했다.
- 한계: 이 Mac의 Command Line Tools에는 XCTest가 없어 `swift test` 대신 저장소의 독립 Swift 검증 스크립트를 실행했다. 시간 텍스트가 없는 격자 셀은 시작 시간을 30분 단위, 길이를 기본 1시간으로 추정하므로 검토가 필요하다. 실제 데스크탑 적용은 구현되어 있지만 개발 검증에서 사용자의 배경화면을 바꾸지는 않았다.

## M003 · 실제 앱 흐름 검증과 결과 화면 · 2026-09-06

- 프롬프트: [P001](prompts/P001.md), [P002](prompts/P002.md)
- 결과: [실제 앱 화면](../artifacts/studio.png)과 [OCR 검토 화면](../artifacts/ocr-review.png)을 기록했다. 원본 이미지 확대(100–300%)와 비활성 버튼의 구분을 보완했다.
- 실제 UI 검증: 한글 이름의 토요일 13:30–14:00 일정을 추가하고, 앱 종료/재실행 후 남아 있음을 확인한 뒤 제거했다. 테마 변경, 빈 시간표, 예시 복원도 확인했다. 테스트 데이터는 기본 예시로 복원했다.
- 실제 UI 검증: 이미지 선택 → Apple Vision 인식 → 과목 4개 검토 → 확인 체크 전 반영 비활성 → 확인 후 반영 → PNG 저장을 끝까지 실행했다. 저장된 [배경화면](../artifacts/ocr-import-wallpaper.png)은 `sips`로 3024 × 1964픽셀임을 확인했다.
- 최종 검증: 개선 사항을 포함한 release 빌드와 앱 서명 검증(`codesign --verify --deep --strict`) 통과. 최종 앱을 재실행해 원본 확대 조작 및 인식 결과를 확인했다. 실제 배경화면 적용 버튼은 사용자가 원할 때 누를 수 있도록 남겼다.
