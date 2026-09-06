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
