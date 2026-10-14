# Tasks: Fence the autonomous loop's PR-quality failure modes (#2905)

**Plan:** `knowledge-base/project/plans/2026-04-27-fix-autoloop-pr-guards-2905-plan.md`

## Phase 1 — Root cause: path allowlist in session-sync.ts

- [x] 1.1 Inventory existing test files that mock `syncPull`/`syncPush`:
  - [x] 1.1.1 Run `grep -l "syncPull: vi.fn\|syncPush: vi.fn" apps/web-platform/test/*.ts` and list affected files.
  - [x] 1.1.2 For each, confirm the mock is a thin `vi.fn()` (no body assertions). If any test asserts on the function body, list it as a Phase 1 dependency.
- [x] 1.2 Write failing test `apps/web-platform/test/session-sync-path-allowlist.test.ts` (TDD RED):
  - [x] 1.2.1 TS-1: dirty workspace with `.claude/settings.json` (modified) AND `knowledge-base/overview/vision.md` (added) → `git add` invoked with explicit `knowledge-base/overview/vision.md` only; `.claude/settings.json` remains uncommitted.
  - [x] 1.2.2 TS-2: dirty workspace with only `.claude/settings.json` modified → no `git add`, no `git commit` invoked; pull still proceeds.
  - [x] 1.2.3 TS-3: dirty workspace with only `.claude/worktrees/agent-deadbeef` present → no commit; allowlist filter rejects it even if it slipped past `.gitignore`.
- [x] 1.3 Run new test — confirm RED:
  - [x] 1.3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/session-sync-path-allowlist.test.ts`
- [x] 1.4 Implement path-scoping helper in `apps/web-platform/server/session-sync.ts`:
  - [x] 1.4.1 Define `ALLOWED_AUTOCOMMIT_PATHS = [/^knowledge-base\//]` near the top of the file.
  - [x] 1.4.2 Add helper `getAllowlistedChanges(workspacePath: string): string[]` — runs `git status --porcelain`, parses each line, filters by regex.
  - [x] 1.4.3 Replace `git add -A` at line 201 with `if (paths.length === 0) return; execFileSync("git", ["add", "--", ...paths], ...)`.
  - [x] 1.4.4 Replace `git add -A` at line 249 with the same pattern.
  - [x] 1.4.5 Add log line `"No allowlisted changes to commit — skipping auto-commit"` for the empty-paths case.
- [x] 1.5 Confirm GREEN: re-run targeted test, expect pass.
- [x] 1.6 Run full vitest suite for web-platform — `cd apps/web-platform && ./node_modules/.bin/vitest run`.
  - [x] 1.6.1 Fix any breakage from the new mock-call shape.
- [x] 1.7 Run `cd apps/web-platform && npx tsc --noEmit` — confirm type-clean.
- [x] 1.8 Commit: `feat(session-sync): scope auto-commit to knowledge-base/ paths (#2905)`.

## Phase 2 — Repo hygiene: .gitignore

- [x] 2.1 Edit `.gitignore` to add `/.claude/worktrees/` (anchored leading slash).
- [x] 2.2 Verify with three test paths:
  - [x] 2.2.1 `git check-ignore -v .claude/worktrees/agent-test` returns the new rule.
  - [x] 2.2.2 `git check-ignore -v .claude/worktrees/` returns the new rule.
  - [x] 2.2.3 `git check-ignore -v knowledge-base/foo.md` returns NOTHING (regression check — knowledge-base must remain trackable).
- [x] 2.3 Commit: `chore(gitignore): add .claude/worktrees/ to ignore stray loop markers (#2905)`.

## Phase 3 — CI guards: pr-quality-guards.yml

- [x] 3.1 Write `.github/scripts/check-settings-integrity.sh`:
  - [x] 3.1.1 Reads `BASE_REF` and `HEAD_REF` env vars.
  - [x] 3.1.2 Composes base and head settings JSON via `git show $REF:.claude/settings.json`.
  - [x] 3.1.3 Computes deleted top-level keys: `hooks`, `enabledMcpjsonServers`, `env`.
  - [x] 3.1.4 Computes deleted `permissions.allow[*]` entries.
  - [x] 3.1.5 Exits non-zero with structured message if any were removed.
  - [x] 3.1.6 Exits 0 if base file does not exist (first-add case).
- [x] 3.2 Write `.github/scripts/check-pr-body-vs-diff.sh`:
  - [x] 3.2.1 Reads `PR_NUMBER` env var.
  - [x] 3.2.2 Fetches PR body via `gh pr view $PR_NUMBER --json body --jq .body`.
  - [x] 3.2.3 Strips fenced code blocks before extracting paths.
  - [x] 3.2.4 Extracts paths via regex `[\w./-]+\.(ts\|tsx\|js\|md\|njk\|yml\|yaml\|json\|sh\|py)`.
  - [x] 3.2.5 Fetches diff paths via `gh pr diff $PR_NUMBER --name-only`.
  - [x] 3.2.6 Computes orphan ratio; fails if <50% of cited paths exist in diff.
  - [x] 3.2.7 Posts a comment via `gh pr comment` listing orphan citations.
  - [x] 3.2.8 Tolerates JSON parse failures with the `cq-ci-steps-polling-json-endpoints-under` guard pattern.
- [x] 3.3 Write `.github/scripts/check-auto-commit-density.sh`:
  - [x] 3.3.1 Reads `PR_NUMBER` env var.
  - [x] 3.3.2 Fetches headlines via `gh pr view $PR_NUMBER --json commits --jq '.commits[].messageHeadline'`.
  - [x] 3.3.3 Counts matches against the regex `^(Auto-commit (before sync pull|after session)|Merge branches 'main' and 'main')$`.
  - [x] 3.3.4 Fails if >50% match.
- [x] 3.4 Write `.github/workflows/pr-quality-guards.yml`:
  - [x] 3.4.1 Trigger: `on: pull_request:` (default activity types — opened, synchronize, reopened, edited).
  - [x] 3.4.2 4 jobs: `settings-json-integrity`, `pr-body-vs-diff`, `stray-worktree-marker-block`, `auto-commit-message-density`.
  - [x] 3.4.3 Each job: `runs-on: ubuntu-latest`, pin `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` (matches `ci.yml:16`).
  - [x] 3.4.4 Each job: first step checks for `confirm:claude-config-change` label; if present, emit `::warning::` and exit 0.
  - [x] 3.4.5 `stray-worktree-marker-block` is a one-liner: `gh pr diff $PR_NUMBER --name-only | grep -E '^\.claude/worktrees/' && exit 1 || exit 0`.
- [x] 3.5 Per the `cq-workflow-pattern-duplication-bug-propagation` rule: scan the workflow for known-buggy idioms before committing:
  - [x] 3.5.1 No piped `| while` loops with counter updates (subshell scope bug).
  - [x] 3.5.2 Every `gh api` call is guarded with `jq -e .` per `cq-ci-steps-polling-json-endpoints-under-bash-e`.
  - [x] 3.5.3 `set -uo pipefail` on every script.
  - [x] 3.5.4 No multi-line heredocs that drop below YAML literal block base indentation per `hr-in-github-actions-run-blocks-never-use`.
- [x] 3.6 Commit: `ci: add pr-quality-guards workflow (#2905)`.

## Phase 4 — AGENTS.md rule

- [x] 4.1 Pre-flight: read `scripts/retired-rule-ids.txt` to ensure `hr-never-git-add-A-in-user-repo-agents` is NOT retired.
  - [x] 4.1.1 `grep -E '^hr-never-git-add-A' scripts/retired-rule-ids.txt` returns nothing.
- [x] 4.2 Pre-flight: measure current AGENTS.md byte count: `wc -c AGENTS.md`. Record current vs 37000 cap headroom.
- [x] 4.3 Add Hard Rule under the "## Hard Rules" section:
  ```
  - In `apps/web-platform/server/session-sync.ts` and similar user-repo agent paths, never use `git add -A` — use a path allowlist (`knowledge-base/**`) [id: hr-never-git-add-A-in-user-repo-agents]. The auto-commit sweep otherwise lands `.claude/settings.json` wipes, stray `.claude/worktrees/` markers, and unrelated drift into PRs the loop never intended to author. **Why:** #2857/#2859 settings wipe + gitlink leak; #2905.
  ```
- [x] 4.4 Verify byte length ≤600: `awk '/hr-never-git-add-A-in-user-repo-agents/ {print length($0)}' AGENTS.md` returns ≤600.
- [x] 4.5 Run `bun test plugins/soleur/test/components.test.ts` — confirm token budget intact.
- [x] 4.6 Run AGENTS.md byte check: `wc -c AGENTS.md` < 37000 (warn) and < 40000 (critical).
- [x] 4.7 Commit: `docs(agents): add path-allowlist rule for user-repo agent commits (#2905)`.

## Phase 5 — Synthetic-violation verification

- [ ] 5.1 Create branch `tmp/test-2905-guards-synthetic` from this branch's tip.
- [ ] 5.2 Make four atomic commits, each violating one guard:
  - [ ] 5.2.1 Commit 1: replace `.claude/settings.json` with `{"permissions":{"allow":[]}}` (settings-integrity violation).
  - [ ] 5.2.2 Commit 2: empty diff but PR body cites `does/not/exist.ts` and `also/missing.md` (body-vs-diff violation).
  - [ ] 5.2.3 Commit 3: add file `.claude/worktrees/agent-test` (stray-marker violation).
  - [ ] 5.2.4 Commit 4: 3 of 4 commits use the auto-commit headline pattern (density violation).
- [ ] 5.3 Push and open a draft PR.
- [ ] 5.4 Watch all 4 guards fail.
- [ ] 5.5 Capture each run URL into the main PR's body under "## Verification".
- [ ] 5.6 Close the synthetic PR, delete `tmp/test-2905-guards-synthetic`.

## Phase 6 — Compound + Ship

- [ ] 6.1 Run `skill: soleur:compound`.
- [ ] 6.2 Write learning file `knowledge-base/project/learnings/<topic>.md` (date assigned at write-time per `cq-do-not-prescribe-exact-learning-filenames-with-dates-in-tasks-md` — directory + topic only).
- [ ] 6.3 Run `skill: soleur:ship` with `semver:patch` label and `Closes #2905` in PR body.
- [ ] 6.4 Post-merge: verify next bot-authored PR's `.files[].path` includes only knowledge-base content (smoke check, not blocking).
