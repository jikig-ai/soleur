# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-drift-guard-install-grant-diff-4179/knowledge-base/project/plans/2026-05-20-feat-drift-guard-installation-grant-diff-4179-plan.md
- Status: complete

### Errors
None

### Decisions
- **Endpoint:** `GET /app/installations?per_page=100` (App-JWT, FLAT array) over `/orgs/{org}/installations`. Reuses the JWT the guard already mints; satisfies `hr-github-app-auth-not-pat`.
- **Reuse, don't fork:** existing `bin/diff-github-app-manifest.sh` invoked verbatim against synthetic per-installation `{permissions, events}` files. No new script, no new test file, no new workflow, no new secret. Net diff ~80 LoC YAML + 25 LoC test.
- **Fold-in #3561 elevated to load-bearing.** Every new failure-mode name contains `f`; the existing `tr -d '\x7f'` bug (parsed as literal `x`/`7`/`f`) would silently mangle every operator-facing mode string. AC13b mandates the `\x7f` -> `\177` octal fix inline.
- **Pagination gated, not looped.** `Link: rel="next"` presence fires `installation_list_truncated` -> `ci/guard-broken` rather than silently iterating only page 1.
- **CPO sign-off required at plan-time** (`requires_cpo_signoff: true` per `single-user incident` threshold carry-forward from brainstorm). `user-impact-reviewer` invoked at PR-review.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Bash (gh CLI, git, awk/grep)
- Read, Edit, Write
- WebFetch, WebSearch
