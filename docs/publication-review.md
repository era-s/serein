# Publication privacy review

Reviewed on **2026-09-13** for [P010](prompts/P010.md).

## Scope and findings

| Area | Review result |
| --- | --- |
| Original Git history | 13 reachable development commits and 160 unique text blobs inspected. |
| Commit metadata | The owner explicitly permits the existing author and committer email to be public. Original commit metadata is retained. |
| Source, prompts, logs, test fixtures | No committed credentials, personal calendar identifiers, private user paths, or private keys found in the inspected text. |
| Historical images | All 24 unique image blobs reviewed with local OCR, metadata inspection, and visual contact sheets. They contain fictional examples, not personal calendars or the uploaded reference photo. No identifying image metadata found. |
| GitHub attachments | No releases, issues, pull requests, Actions runs/artifacts, Pages site, or forks at the time of review. |
| New README gallery | Six 3840 × 2160 renders made from fictional fixtures. No personal input or upscaling. |

## Publication approach

The existing repository is renamed to `serein` and made public with its original development history. No history rewrite is needed: the owner explicitly confirmed that the commit author email may be public.

Actual personal timetables, calendar screenshots, uploaded source images, local backups, and signing credentials are excluded. All new gallery images use fictional fixtures. The temporary review copy remains private and is not the public project.

This review concerns accidental disclosure through the repository. It is not a guarantee that every possible vulnerability has been found, and it does not audit files outside the publication scope. The GitHub account handle, development dates, original product requests, and fictional examples are intentionally public.

## Keeping future changes safe

- Keep commit metadata consistent with the owner’s publication preferences.
- Keep personal `studio.json`, wallpapers, system backups, keychains, keys, and signing passwords outside Git.
- Use fictional fixtures for screenshots and gallery images.
- Check staged changes and commit metadata before pushing. `.gitignore` is a convenience, not a secret scanner.

The [development log](devlog.md) records the actual verification and publication milestones. Raw audit output and the original email are not included here.

---

## 한국어 요약

사용자가 기존 커밋 작성자 이메일의 공개를 허용했습니다. 따라서 원래 개발 이력을 유지한 채 기존 저장소를 `serein`으로 이름 변경하고 공개합니다. 검토용 복사본은 비공개이며 공개 프로젝트가 아닙니다.

검토한 소스·기록·가상 예시 이미지에서 인증 정보나 개인 캘린더 데이터는 발견하지 못했습니다. **실제 시간표·개인 캘린더 화면·업로드한 원본 사진은 공개하지 않습니다.** 새 4K 이미지 6종은 가상 일정으로 만들었으며 기존 이미지 24개도 확인했습니다. 개인 작업과 서명 정보는 로컬에만 보관합니다.
