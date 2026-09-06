---
name: prompt-ledger
description: Record development milestones in a GitHub repository with original user prompts, result artifacts, verification evidence, and commit trailers. Use when the user asks for prompt-to-result traceability or a development history tied to prompts.
---

# Prompt ledger

Keep each source prompt traceable to the exact committed result. Use the repository's existing conventions if it already has a ledger; otherwise use the lightweight layout below.

- Assign consecutive IDs such as `P001` in `docs/prompts/`. Preserve the user's exact request in a clearly marked source section. Keep implementation decisions and progress separate; never rewrite the source to fit the result. For attachments, record a descriptive filename and relevant visual observations, not local private paths or an automatic copy of the attachment.
- At a meaningful working milestone, append an entry to `docs/devlog.md` with its prompt IDs, actual changes, relative links to relevant files or screenshots, and the verification actually performed. Record limitations when they affect the result. Do not describe planned work as complete.
- Commit the relevant changes with a trailer for each governing prompt, for example `Prompt-ID: P001` and `Prompt-ID: P002`. The commit itself is the exact result snapshot; no document needs to contain its own commit hash. Find snapshots with `git log --all --extended-regexp --grep='^Prompt-ID: P001$' --format='%h %s'`.
- Use GitHub CLI (`gh`) for repository creation and inspection, and Git for commits and pushes. Respect the user's repository visibility; when private is requested, create with `--private` and verify `gh repo view --json nameWithOwner,isPrivate,url` before the initial push. Existing session authorization to create the repository and push milestones is sufficient. This skill does not grant authorization for unrelated repositories, publishing, messages, or destructive Git operations.
- Before each checkpoint, inspect the diff and stage only files that belong to the milestone. Do not commit secrets, local caches, unrelated work, or uploaded input images by default. Prefer concise milestones over a commit for every small edit. If authentication or push fails, retain the local checkpoint, report the exact blocker, and continue useful local work; do not claim the remote was updated.

When reporting a finished milestone, provide the repository or commit link plus the relevant prompt IDs. A later prompt should receive its own ID while retaining references to earlier prompts that still govern the result.
