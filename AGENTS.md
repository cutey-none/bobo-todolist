# Repository Agent Guidelines

## Development workflow

- Follow normal open-source collaboration practices: keep changes scoped, readable, and easy to review; do not mix unrelated cleanup into a feature or fix.
- Make small, atomic commits. Each commit should represent one coherent concern and should build or pass its relevant checks whenever practical.
- Prefer Conventional Commit-style messages such as `feat:`, `fix:`, `test:`, `docs:`, and `refactor:`. Describe the observable outcome, not the editing process.
- Before every commit, inspect `git status`, `git diff --check`, and the staged diff. Preserve existing user changes and never include unrelated or generated files accidentally.
- Separate implementation, tests, documentation, and verification artifacts when that makes the history easier to review or revert.
- For user-facing UI changes, save real runtime verification screenshots under `docs/verify/` and document what each screenshot proves.

## Task description product constraints

- A todo item opens as one detail page: the item title is the page-level heading and the content beneath it is an editable description.
- The description may contain small headings, body text, ordinary bullet lists, and images.
- Do not turn description content into subtasks, checklists, progress entries, or an activity timeline unless the user explicitly changes the product direction.
- Description content must persist locally, survive relaunch, and preserve compatible legacy notes/progress data during migration.
