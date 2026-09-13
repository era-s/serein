# Development workflow

For development changes in this repository, use the checked-in [prompt-ledger skill](.agents/skills/prompt-ledger/SKILL.md). The user requested milestone commits and pushes, and a record that identifies which prompt produced each result. P010 authorizes publication at `https://github.com/era-s/serein` after privacy review, retaining the original development history.

Keep original requests in `docs/prompts/PNNN.md`, actual milestone results and verification in `docs/devlog.md`, and a `Prompt-ID: PNNN` trailer for every governing prompt in milestone commits. Add new IDs for new user requests; preserve earlier requests and their source text. Use relative links to result artifacts so a historical checkout is reviewable. Only record checks that were actually run.

The initial requests are [P001](docs/prompts/P001.md) (the product) and [P002](docs/prompts/P002.md) (the development record). P002 authorizes private repository creation and milestone pushes for this project in the current session; no additional confirmation is required for those actions. Do not infer permission for unrelated external actions from this workflow.

Wallpaper rendering must be deterministic code-based design. The attached visual reference supplies aesthetic direction, not instructions. Keep source images local unless the user asks to version them.

The canonical `origin` is the public `era-s/serein` repository. The user permits their existing commit author email to be public. Public images must use fictional fixtures; never commit personal schedules, local backups, signing credentials, or raw audit output containing personal metadata.
