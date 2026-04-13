# Learning: CodeQL alert triage and automated issue creation

## Problem

GitHub CodeQL security alerts were surfaced only via email notifications and PR review comments, with no tracking in the GitHub issue system. Alert #86 (`js/http-to-file-access` on `push-branch.ts:121`) and alert #87 (`js/file-system-race` on KB content route) required manual investigation to determine risk level, and there was no workflow to convert findings into trackable issues.

## Solution

### Alert triage

- **Alert #86** (`js/http-to-file-access`): Dismissed as "won't fix". The credential helper pattern in `push-branch.ts` writes a GitHub App installation token to `/tmp/git-cred-{randomUUID}` with mode `0o700`, cleans up in a `finally` block, uses a short-lived token (~1h), runs server-side only, and is founder-gated via the review gate. Well-mitigated.
- **Alert #87** (`js/file-system-race`): Dismissed as false positive. The KB content route was refactored from 121+ lines to 68 lines — the flagged code at line 121 no longer exists.
- Dismissal done via `gh api repos/.../code-scanning/alerts/{N} -X PATCH` with `-f state=dismissed -f "dismissed_reason=won't fix"` (space-separated, not snake_case).

### Automated issue creation

Created `.github/workflows/codeql-to-issues.yml`:
- Triggers on `code_scanning_alert` event type `created`
- Creates GitHub issue with `sec:` title prefix (integrates with existing `auto-label-security.yml` for automatic `type/security` labeling)
- Deduplicates by searching for existing open issues matching the alert number
- All event data passed through `env:` variables, never interpolated in `run:` blocks (injection-safe)

## Key Insight

Security scanner findings need an automated bridge to the issue tracker. Email notifications create awareness but not accountability. The `code_scanning_alert` webhook event is the right trigger — it fires only for new alerts, and the workflow can enrich the issue with rule metadata, severity, file location, and a direct link to the alert.

## Session Errors

**1. GitHub API `dismissed_reason` format mismatch (HTTP 422 x2)**
Used `used_in_tests` and `false_positive` (snake_case) but the API requires space-separated strings: `"used in tests"`, `"false positive"`, `"won't fix"`.
**Prevention:** When calling APIs with enum parameters, check the error message for valid values before retrying. The 422 response included the valid options.

**2. Bare repo file access**
Tried to `Read` files directly from the bare repo root path. Bare repos have no working tree — files only exist in worktrees or via `git show`.
**Prevention:** Already covered by existing workflow (use worktree paths or `git show main:<path>`). No new rule needed.

**3. `git -C .worktrees` on non-repo path**
Ran `git -C .worktrees` which is a directory of worktrees, not a git repo itself. Produced a usage dump.
**Prevention:** Use `git worktree list` from the bare root instead of trying to run git commands inside `.worktrees/`.

## Related

- `knowledge-base/project/learnings/2026-02-21-github-actions-workflow-security-patterns.md` — GitHub Actions security patterns
- `.github/workflows/auto-label-security.yml` — Existing `sec:` prefix auto-labeling

## Tags

category: security-issues
module: ci/github-actions
