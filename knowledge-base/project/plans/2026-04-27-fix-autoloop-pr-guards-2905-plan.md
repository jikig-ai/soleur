# Plan: Fence the autonomous loop's PR-quality failure modes (#2905)

**Issue:** [#2905](https://github.com/jikig-ai/soleur/issues/2905)
**Type:** bug / hardening
**Priority:** P1 (priority/p1-high)
**Domain:** engineering (CTO), operations (COO)
**Branch:** `feat-one-shot-2905-autoloop-pr-guards`

## Overview

The autonomous loop (Command Center web app, `apps/web-platform/server/session-sync.ts`) committed and pushed three classes of failure across PRs #2857 and #2859 that, together, would silently broken the rule-enforcement layer of this repo if either had merged:

1. **PR descriptions disconnected from diffs** — body claims edits to `_includes/base.njk`; diff has zero changes there. Body was generated against the agent's *intent*, not the *diff*.
2. **Destructive `.claude/settings.json` wipe** — both PRs replace the live settings (6 hooks, MCP allowlist, effort level, bash permissions) with `{ "permissions": { "allow": [] }, "sandbox": { "enabled": true } }`. This is unrelated to either PR's stated purpose. The wipe is repeatable across every PR the loop opens.
3. **Stray gitlink commit** — PR #2859 committed `.claude/worktrees/agent-a8cf89db` as mode 160000 (gitlink → unreachable commit `be0378ce…`). Worktree marker files in `.claude/worktrees/` should never be tracked.

The auto-commit messages (`Auto-commit before sync pull`, `Auto-commit after session`, `Merge branches 'main' and 'main' of …`) come from `apps/web-platform/server/session-sync.ts` lines 207 and 255 — `syncPull` runs `git add -A && git commit -m "Auto-commit before sync pull"` at session start (line 194-213), and `syncPush` runs `git add -A && git commit -m "Auto-commit after session"` at session end (line 242-261). These two `git add -A` calls scoop **everything** in the workspace tree — settings drift, stray worktree markers, doc edits the agent never explicitly committed — into whatever feature branch the loop was nominally working on.

This plan fences the three observed failure modes with a defense-in-depth approach: stop the loop from sweeping ambient state into PRs (root cause), and add a CI gate that blocks the wipe + gitlink patterns even if a future drift re-introduces them (containment).

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "Both PRs replace the live settings.json with `{permissions: {allow: []}, sandbox: {enabled: true}}`" | Confirmed via `gh pr view 2857 --json files` — `.claude/settings.json` modified `+3/-71`. Live settings has 6 hooks, MCP allowlist, env, and 5 Bash permission entries. | Add CI gate `lint-settings-json-integrity` that blocks PRs deleting any `hooks.*`, `enabledMcpjsonServers`, or `env.CLAUDE_CODE_EFFORT_LEVEL` keys without an opt-in label. |
| "Auto-commit before sync pull / Auto-commit after session messages" | Confirmed in `apps/web-platform/server/session-sync.ts:207` and `:255`. Both run `git add -A` then `git commit -m "..."`. | Replace `git add -A` with a path-scoped allowlist: only commit paths under `knowledge-base/`. Reject (skip without committing) `.claude/`, `.github/`, `apps/`, `plugins/`, `scripts/`, top-level config files. |
| "PR #2859 committed `.claude/worktrees/agent-a8cf89db` as mode 160000 (gitlink)" | Confirmed via `gh pr view 2859 --json files`. `.claude/worktrees/` is NOT in `.gitignore` — current rule is `.worktrees` (matches a directory named exactly `.worktrees` at any level), which does not match `.claude/worktrees/agent-*`. | Add `.claude/worktrees/` to `.gitignore`. Also add a defense-in-depth check in `syncPull`/`syncPush`: refuse to `git add` paths inside `.claude/worktrees/`. |
| "PR descriptions describe intent the diff does not implement" | Confirmed: PR #2857 body claims edits to `_includes/base.njk`; `gh pr view 2857 --json files` shows zero changes to that file. | Add CI gate `lint-pr-body-vs-diff` that scans the PR body for `\.[a-z]+` filename patterns and verifies each cited file appears in the diff. Failures attach a label and post a comment. |
| "All commits across both PRs use auto-generated messages" | Confirmed via `gh pr view --json commits`. 4 of 4 commits in #2857 and 4 of 5 commits in #2859 use the auto-generated headlines. | Make the auto-commit messages a *signal* CI can detect. Add CI gate that blocks PRs where >50% of commit headlines match the auto-commit regex `^(Auto-commit (before sync pull\|after session)\|Merge branches 'main' and 'main')$`, requiring a human-readable squash-merge message at minimum. |

## Open Code-Review Overlap

None. Searched 21 open `code-review` issues; no matches against any planned-edit path.

## Hypotheses

### Root cause (confirmed by codebase reading)

The autonomous loop in `apps/web-platform` is a connected-repo agent running in an ephemeral container against the user's GitHub repo (path: `user.workspace_path` from the `users` table). At session boundaries:

1. **Session start (`syncPull`, line 179-227):** runs `git status --porcelain`; if non-empty, runs `git add -A && git commit -m "Auto-commit before sync pull"`. Then `git pull --no-rebase --autostash`.
2. **Session end (`syncPush`, line 233-292):** same pattern: `git add -A && git commit -m "Auto-commit after session"`. Then `git push`.

The push targets whatever branch the workspace is currently on. When the agent had checked out a feature branch (`fix/2831-critical-css-lcp-inline`) to do its actual work, the auto-commit at session start swept the **dirty working-tree state from the previous session** — `.claude/settings.json` edits, stray `.claude/worktrees/agent-*` markers, accumulated `vision.md` / `constitution.md` edits — into that feature branch. The `gh pr create` that followed picked up those commits.

The settings.json wipe pattern (`{ "permissions": { "allow": [] }, "sandbox": { "enabled": true } }`) is consistent with **Claude Code's default settings.json** when no `.claude/settings.json` exists. This suggests one of:

- The agent's workspace was reset/re-cloned at some point, replacing the committed `.claude/settings.json` with the default.
- The agent itself wrote that file (e.g., via Write tool) at session start to "ensure sandbox is enabled," not realizing it was clobbering committed config.

Either way, the auto-commit + auto-push chain made the change irreversible from the loop's perspective.

### Why CI didn't catch it

- `web-platform-build` runs `next build` — doesn't validate `.claude/settings.json` shape.
- `test` runs the bun test suite — doesn't read `.claude/settings.json`.
- `lockfile-sync` checks `package-lock.json` — unrelated.
- No existing job inspects PR body, diff scope, or settings integrity.

The blast radius is silent: the PR's CI passes (no test depends on hooks running in CI), the description reads plausibly, and the settings wipe takes effect only **after merge**, when day-2 enforcement (commit-on-main block, conflict-marker block, milestone enforcement, write-guard, security reminder, docs CLI verification) silently disappears.

## Approach

Three layers of defense, **in order of authority**:

### Layer 1 — Root-cause fix in `session-sync.ts` (highest priority)

Stop the loop from sweeping ambient state into feature branches. Replace `git add -A` with a path-scoped allowlist:

- **Allow:** `knowledge-base/**` (the user's content, the actual purpose of the connected repo).
- **Reject silently:** `.claude/**`, `.github/**`, `apps/**`, `plugins/**`, `scripts/**`, `*.json` at root, `*.md` at root (license, readme, agents, claude), `.gitignore`, `.mcp.json`, `_includes/**`, `_data/**`.

Rationale: the connected-repo product surface is *user knowledge content*, not Soleur-internal config. If the agent legitimately needs to modify `.claude/settings.json` (a future "edit my agent config" feature), that's an explicit Write operation the loop should commit deliberately — not sweep silently.

### Layer 2 — Repo hygiene fix in `.gitignore`

Add `.claude/worktrees/` to `.gitignore`. The current `.worktrees` entry only matches a directory named exactly `.worktrees`, not `.claude/worktrees/`.

### Layer 3 — CI gate `pr-quality-guards.yml`

Defense-in-depth: catch the failure modes even if a future drift re-introduces them (e.g., a developer adds back `git add -A` without realizing the precedent).

Three independent jobs, all on `pull_request`:

1. **`settings-json-integrity`** — diff `.claude/settings.json` against `main`; if any of `hooks.*`, `enabledMcpjsonServers`, `env.CLAUDE_CODE_EFFORT_LEVEL`, or any `permissions.allow` entry is **deleted** (not modified, not added — specifically removed), fail with a message linking #2905 and instructing the contributor to add a `confirm:claude-config-change` label to override.

2. **`pr-body-vs-diff`** — extract file paths from the PR body (regex matches like `apps/web-platform/server/foo.ts`, `_includes/base.njk`, `path/to/file.md`). For each extracted path, check that it appears in `gh pr diff --name-only`. If <50% of cited paths are in the diff, fail with a comment listing the orphan citations.

3. **`stray-worktree-marker-block`** — fail if any path matching `^\.claude/worktrees/` appears in the diff. (Defense-in-depth — should already be unreachable after Layer 2.)

4. **`auto-commit-message-density`** — fail if >50% of commit headlines on the PR branch match `^(Auto-commit (before sync pull|after session)|Merge branches 'main' and 'main')$`. The squash-merge message is *not* the issue (squash always produces a single commit) — the issue is that PR review reads the per-commit list.

All four jobs are **opt-out via the same label** (`confirm:claude-config-change`) for the rare case where a PR legitimately modifies these surfaces.

## Files to Create

- `.github/workflows/pr-quality-guards.yml` — the four-job CI workflow described above.
- `.github/scripts/check-settings-integrity.sh` — bash script invoked by `settings-json-integrity` job. Accepts `BASE_REF` and `HEAD_REF` env vars, exits non-zero with a summary message on violation.
- `.github/scripts/check-pr-body-vs-diff.sh` — bash script invoked by `pr-body-vs-diff` job. Accepts `PR_NUMBER` env var; uses `gh pr view` and `gh pr diff --name-only`.
- `.github/scripts/check-auto-commit-density.sh` — bash script invoked by `auto-commit-message-density` job.
- `apps/web-platform/test/session-sync-path-allowlist.test.ts` — vitest covering the new path-scoping logic.
- `apps/web-platform/test/fixtures/dirty-workspace.ts` — helper to construct a dirty workspace with a mix of allowed and rejected paths.
- `knowledge-base/project/learnings/2026-04-27-autoloop-pr-quality-failure-modes.md` — postmortem learning (created at compound phase, not work phase).

## Files to Edit

- `apps/web-platform/server/session-sync.ts` — replace `git add -A` (line 201, line 249) with a path-scoped helper. Skip the commit entirely if no allowlisted paths have changes after the filter.
- `.gitignore` — add `.claude/worktrees/` (anchored: `/.claude/worktrees/` to be unambiguous about the location).
- `.github/workflows/ci.yml` — add `pr-quality-guards` workflow as a separate file (NOT inside ci.yml, to keep concerns separated and let the new workflow ship as a discrete unit). Reference here is informational only — no edit to `ci.yml` needed.
- `apps/web-platform/test/session-sync-existing-tests.ts` — sweep existing session-sync tests for `git add -A` mocks; rewrite to assert the new allowlist-aware mock interface. (Search `apps/web-platform/test/` for any test that imports `syncPull` or `syncPush` — current grep shows 11 files mock these as `vi.fn()`, which is fine. But any test that validates the *body* of those mocks needs to update to the new signature.)
- `AGENTS.md` — add ONE rule under Hard Rules capturing: "When adding `git add` calls in connected-repo agent code paths (`apps/web-platform/server/session-sync.ts`, `push-branch.ts`, or anything that pushes to a user's repo), use a path allowlist — never `git add -A`. **Why:** #2905."

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/server/session-sync.ts` replaces both `git add -A` calls with a path-scoped helper that commits only `knowledge-base/**` paths. Confirmed by:
  - [ ] `rg "git add -A" apps/web-platform/server/session-sync.ts` returns zero hits.
  - [ ] New unit test: dirty workspace with `.claude/settings.json` modified and `knowledge-base/foo.md` added → only `knowledge-base/foo.md` is staged; `.claude/settings.json` is left dirty (uncommitted, not pushed).
  - [ ] New unit test: dirty workspace with only `.claude/settings.json` modified → no commit is created; `git log` shows no `Auto-commit` headline.
  - [ ] New unit test: dirty workspace with only `.claude/worktrees/agent-X` present → no commit is created.
- [ ] `.gitignore` adds `/.claude/worktrees/` (anchored). Confirmed by:
  - [ ] `git check-ignore -v .claude/worktrees/agent-test` returns the new rule.
  - [ ] `git check-ignore -v .claude/worktrees/` returns the new rule.
- [ ] `.github/workflows/pr-quality-guards.yml` exists with 4 jobs: `settings-json-integrity`, `pr-body-vs-diff`, `stray-worktree-marker-block`, `auto-commit-message-density`. Confirmed by:
  - [ ] `gh workflow view pr-quality-guards.yml` returns the workflow.
  - [ ] All 4 jobs run on this PR (the workflow's first run validates itself).
  - [ ] All 4 jobs pass on this PR.
- [ ] One AGENTS.md rule added under Hard Rules (≤600 bytes), capturing the `git add -A` ban for user-facing repo agents. Rule ID: `hr-never-git-add-A-in-user-repo-agents`.
  - [ ] `awk '/hr-never-git-add-A-in-user-repo-agents/ {print length($0)}' AGENTS.md` ≤600.
  - [ ] `bun test plugins/soleur/test/components.test.ts` passes (token budget intact).
- [ ] All four CI guard jobs successfully detect a synthetic violation. Verified by:
  - [ ] Test branch `tmp/test-2905-guards` (deleted before merge) demonstrates each guard firing on a synthetic violation. Append the run URL of each detection to the PR body's "Verification" section.

### Post-merge (operator)

- [ ] After merge, run `gh workflow run pr-quality-guards.yml` (workflow_dispatch is intentionally not added; this gate is `pull_request`-only). Skip — no manual run needed.
- [ ] Verify next autonomous-loop session does **not** sweep `.claude/settings.json` into a PR. Spot-check the next bot-fix PR opened by `app/soleur-ai`: `gh pr view <N> --json files | jq '.files[].path'` should show only `knowledge-base/**` paths plus the actual fix.
- [ ] Verify the rule-metrics aggregator records the new rule. `gh workflow run rule-metrics-aggregate.yml` then check that `hr-never-git-add-A-in-user-repo-agents` appears in `knowledge-base/project/rule-metrics.json` after the next Sunday run. (Stretch — not blocking for issue closure.)
- [ ] Close #2905 with `gh issue close 2905 --reason completed --comment "Fixed in PR #<N>: …"`.

## Test Scenarios

### TS-1: Path allowlist filters `.claude/` writes

**Setup:** Mock `execFileSync` to simulate a workspace with `.claude/settings.json` (modified) and `knowledge-base/overview/vision.md` (added). Call `syncPull(userId, workspacePath)`.

**Expected:**
- `git add` is called with explicit path `knowledge-base/overview/vision.md` only — never with `-A`.
- `.claude/settings.json` remains in `git status --porcelain` after the call (still dirty, not staged, not committed).
- `git commit -m "Auto-commit before sync pull"` is invoked (because the allowlist has at least one path with changes).

### TS-2: All-rejected paths produce no commit

**Setup:** Mock workspace with only `.claude/settings.json` modified (no `knowledge-base/**` changes).

**Expected:**
- No `git add` is invoked.
- No `git commit` is invoked.
- `git pull` proceeds normally (the allowlist filter does not gate the pull itself).
- Log line: `"No allowlisted changes to commit — skipping auto-commit"`.

### TS-3: Stray `.claude/worktrees/` marker is rejected

**Setup:** Mock workspace with `.claude/worktrees/agent-deadbeef` present (any content, including a gitlink).

**Expected:**
- The path is filtered out of the allowlist.
- If no other allowlisted changes exist, no commit is created.
- `.gitignore`'s `/.claude/worktrees/` entry means `git status --porcelain` should not even list this file in normal operation; the allowlist filter is defense-in-depth.

### TS-4: CI guard `settings-json-integrity` blocks a wipe

**Setup:** Synthetic test branch with a commit that replaces `.claude/settings.json` with `{"permissions":{"allow":[]},"sandbox":{"enabled":true}}`.

**Expected:**
- `pr-quality-guards / settings-json-integrity` job fails on PR open.
- Failure message lists the deleted top-level keys (`hooks`, `enabledMcpjsonServers`, `env`, `permissions.allow[*]`).
- Adding the `confirm:claude-config-change` label and re-running the workflow makes the job pass with a `::warning::` annotation instead.

### TS-5: CI guard `pr-body-vs-diff` blocks a fabricated description

**Setup:** Synthetic PR with a body claiming edits to `_includes/base.njk` and `apps/web-platform/server/foo.ts`, but the diff only changes `knowledge-base/overview/vision.md`.

**Expected:**
- `pr-quality-guards / pr-body-vs-diff` job fails.
- Comment posted: lists the orphan citations and the actually-changed paths.

### TS-6: CI guard `auto-commit-message-density` blocks a sweep PR

**Setup:** Synthetic PR with 4 commits, 3 of which have headlines `Auto-commit before sync pull` and 1 has `feat: add real change`.

**Expected:**
- `pr-quality-guards / auto-commit-message-density` job fails (75% match rate, threshold is >50%).

## Hypotheses (Network/Outage Checklist)

This plan does NOT match any of the SSH/network-connectivity trigger patterns (no SSH, no `kex`, no `502/503/504`, no `handshake`, no `firewall`, no `timeout`, no `unreachable`). Section skipped per skill `1.4`.

## Domain Review

**Domains relevant:** Engineering (CTO), Operations (COO).

### Engineering (CTO)

**Status:** carry-forward (issue body explicitly invokes CTO as suggested investigation owner).
**Assessment:** This is a workflow/infra plan — three layers of defense in depth, all in CI/server-side code, no UI surface. Standard engineering pattern: stop sweeping ambient state (root cause), tighten `.gitignore` (hygiene), add CI guards (containment). No architectural concerns. Risk surface is well-bounded: the `git add -A → allowlist` change has clear test coverage; CI guards are opt-out via label so legitimate edits are not gated forever.

### Operations (COO)

**Status:** carry-forward (issue body explicitly invokes COO as suggested investigation owner).
**Assessment:** The autonomous loop currently runs as `ops@jikigai.com` / `agent@soleur.ai`. The `Auto-commit before sync pull` / `Auto-commit after session` pattern is a **product feature** of the connected-repo runtime — operators expect their workspace state to be persisted between sessions. The fix is **not** to remove the auto-commit (that breaks the product feature) but to **scope what gets auto-committed**. The path allowlist (`knowledge-base/**`) preserves the product feature for the actual product surface (user knowledge content) while fencing the side channel (settings/worktree markers). No operational risk to the loop itself; expect zero behavior change for users whose connected repos contain only `knowledge-base/` edits.

### Product/UX Gate

**Tier:** none (infrastructure / CI / server-side code; no user-facing UI surface modified).

## Risks

1. **Path allowlist is too narrow.** If a legitimate connected-repo workflow expects to commit *outside* `knowledge-base/` (e.g., a user putting their own `.github/workflows/` in the repo we're hosting), the loop now skips those commits silently. **Mitigation:** the allowlist is in code, easy to extend; document the allowlist explicitly in the function comment so the next reader knows where to add paths. **Verification:** the connected-repo product is currently scoped to knowledge-base content per `apps/web-platform/server/agent-runner.ts:495` system prompt ("Use the tools available to you to read and write to the knowledge-base directory"). The agent should never be writing outside `knowledge-base/` in normal operation.

2. **CI guards add latency.** Four new jobs on every PR — bash-only, no Docker pull, ≤30s each. Acceptable.

3. **`pr-body-vs-diff` false positives.** A PR body might cite a file path inside a code-fenced block (showing what the file *previously* looked like, or describing a related-but-untouched file). **Mitigation:** the regex extracts paths only from prose (outside ``` fences), and the threshold is 50% — a single orphan citation in a 3-citation body still passes. The label `confirm:claude-config-change` is also an opt-out.

4. **`auto-commit-message-density` rejects legitimate squash-merge bots.** A separate bot that opens PRs from commits with auto-generated headlines (e.g., dependabot's `chore(deps):`) might trip the guard. **Mitigation:** the regex is anchored to the *specific* `Auto-commit ...` strings from `session-sync.ts`, not a generic auto-commit pattern. Dependabot, renovate, etc. won't match.

5. **The settings wipe could re-occur from a different code path.** This plan does not investigate *why* the loop's workspace had a fresh default `.claude/settings.json`. Hypothesis: workspace re-clone replaced the committed file. **Mitigation:** Layer 3's `settings-json-integrity` CI guard catches the wipe even if Layer 1's path filter misses (e.g., if `.claude/settings.json` ever gets added to the allowlist for a feature, the CI guard remains).

6. **The bot-PR labeler might mis-match in the per-commit headline check.** The 4-job workflow uses `gh pr view --json commits --jq '.commits[].messageHeadline'` to enumerate. **Mitigation:** test on a real PR (this one) before merge.

## Alternative Approaches Considered

| Approach | Rejected reason |
|---|---|
| **Remove the auto-commit entirely.** | Breaks the connected-repo product feature: users expect their work to persist between sessions. |
| **Block `.claude/**` in the auto-commit; allow everything else.** | Too narrow — doesn't fence `.github/`, `apps/`, etc. The agent should be writing to `knowledge-base/` only; an allowlist is more precise than a denylist for this surface. |
| **Make the auto-commit messages user-readable (e.g., reference the LLM's intent).** | Doesn't address the root cause: the *files swept in* were wrong, not the message. A nicer message on a settings-wipe commit is still a settings-wipe commit. |
| **Add a `git diff --name-only` review prompt to the LLM before commit.** | Non-deterministic; relies on LLM behavior. The path allowlist is mechanical and auditable. |
| **Move `.claude/settings.json` out of the connected-repo workspace.** | Would mean the agent can't see its own enforcement config — defeats the point of having hooks at all. |

## Implementation Phases

### Phase 1 — Root cause (session-sync.ts)

1. Read existing tests in `apps/web-platform/test/` that mock `syncPull`/`syncPush` (currently 11 files — confirm via `grep -l 'syncPull: vi.fn' apps/web-platform/test/*.ts`).
2. Write failing test `apps/web-platform/test/session-sync-path-allowlist.test.ts` covering TS-1 through TS-3 (RED).
3. Implement path-scoping helper in `session-sync.ts`:
   - Define `ALLOWED_PATHS = [/^knowledge-base\//]`.
   - Helper `getAllowlistedChanges(workspacePath: string): string[]` — runs `git status --porcelain`, filters by `ALLOWED_PATHS`, returns the file paths.
   - Replace `git add -A` (lines 201 and 249) with `if (paths.length === 0) skip-commit; else git add <paths...>`.
4. Run new test (GREEN).
5. Run full vitest suite — fix any test breakage from the mock-shape change.

### Phase 2 — Repo hygiene (.gitignore)

1. Add `/.claude/worktrees/` to `.gitignore`. Anchored leading slash specifies the location unambiguously.
2. Verify with `git check-ignore -v .claude/worktrees/agent-x`.

### Phase 3 — CI guards (pr-quality-guards.yml)

1. Write `.github/scripts/check-settings-integrity.sh`:
   - Inputs: `BASE_REF`, `HEAD_REF`.
   - Use `git diff $BASE_REF $HEAD_REF -- .claude/settings.json | jq` (compose: `git show $BASE_REF:.claude/settings.json | jq` and `git show $HEAD_REF:.claude/settings.json | jq`).
   - Compute set of top-level keys + `permissions.allow[*]` entries removed.
   - Exit non-zero with a structured message if any were removed.
2. Write `.github/scripts/check-pr-body-vs-diff.sh`:
   - Input: `PR_NUMBER`.
   - Extract file path strings from `gh pr view $PR_NUMBER --json body --jq .body` (regex: `[\w/.-]+\.(ts\|tsx\|js\|md\|njk\|yml\|yaml\|json\|sh\|py)`), excluding paths inside fenced code blocks.
   - Get diff paths via `gh pr diff $PR_NUMBER --name-only`.
   - Compute orphan ratio; fail if <50% of cited paths exist in diff.
3. Write `.github/scripts/check-auto-commit-density.sh`:
   - Input: `PR_NUMBER`.
   - Get headlines via `gh pr view $PR_NUMBER --json commits --jq '.commits[].messageHeadline'`.
   - Count matches against the regex `^(Auto-commit (before sync pull|after session)|Merge branches 'main' and 'main')$`.
   - Fail if >50% match.
4. Write `.github/workflows/pr-quality-guards.yml`:
   - `on: pull_request:` (default activity types).
   - 4 jobs, each `runs-on: ubuntu-latest`, each invoking its bash script.
   - Each job: check for `confirm:claude-config-change` label first; if present, emit `::warning::` and exit 0.
   - Use `actions/checkout@v4.3.1` (pinned SHA, matches existing repo style).
5. Verify all four jobs run and pass on this PR's HEAD.

### Phase 4 — AGENTS.md rule

1. Add Hard Rule:
   ```
   - In `apps/web-platform/server/session-sync.ts` and similar user-repo agent paths, never use `git add -A` — use a path allowlist (`knowledge-base/**`) [id: hr-never-git-add-A-in-user-repo-agents]. The auto-commit sweep otherwise lands `.claude/settings.json` wipes, stray `.claude/worktrees/` markers, and unrelated drift into PRs the loop never intended to author. **Why:** #2857/#2859 settings wipe + gitlink leak; #2905.
   ```
2. Verify byte length ≤600 with `awk '/hr-never-git-add-A/ {print length($0)}' AGENTS.md`.
3. Run `bun test plugins/soleur/test/components.test.ts` — confirm token budget intact.

### Phase 5 — Synthetic-violation verification

Before merging:

1. Create a temporary branch `tmp/test-2905-guards-synthetic` from this branch's tip.
2. Make four atomic commits, each violating one guard:
   - Commit 1: replace `.claude/settings.json` with `{"permissions":{"allow":[]}}`.
   - Commit 2: PR body cites `does/not/exist.ts`.
   - Commit 3: add `.claude/worktrees/agent-test`.
   - Commit 4: amend 3 commits with `Auto-commit before sync pull` headlines.
3. Push, open a draft PR, watch all 4 guards fail.
4. Capture each run URL into the main PR's body under "Verification".
5. Close the synthetic PR, delete the branch.

### Phase 6 — Compound + ship

1. Run `skill: soleur:compound` — record the failure-mode classification + fix shape.
2. Write learning file `knowledge-base/project/learnings/2026-04-27-autoloop-pr-quality-failure-modes.md`.
3. Run `skill: soleur:ship` — semver:patch (bug fix), `Closes #2905` in body.

## CLI-Verification Gate

This plan prescribes the following CLI invocations — all verified against existing repo usage (no new tools introduced):

- `gh pr view <N> --json files,commits,body` — used widely in `.github/workflows/scheduled-bug-fixer.yml:208,222,232,...`. <!-- verified: 2026-04-27 source: existing usage -->
- `gh pr diff <N> --name-only` — used in `.github/workflows/scheduled-bug-fixer.yml:232`. <!-- verified: 2026-04-27 source: existing usage -->
- `git check-ignore -v <path>` — standard git porcelain, zero risk. <!-- verified: 2026-04-27 source: git docs -->
- `bun test plugins/soleur/test/components.test.ts` — used in `plugins/soleur/AGENTS.md` Token Budget Check. <!-- verified: 2026-04-27 source: plugins/soleur/AGENTS.md -->

No fabricated CLI tokens.

## Sharp Edges

- **Do not test the path allowlist by greping `node_modules/.bin/git` or similar.** The unit tests use `vi.mock` against `child_process` to capture `execFileSync` calls — that's the boundary.
- **Do not extend the allowlist to include `.claude/`** even for a "fix the wipe" feature. The wipe should be caught by the CI guard, not silently auto-committed with a different path scope. If a legitimate connected-repo feature ever needs to write `.claude/settings.json`, that's an explicit Write tool call followed by an explicit `git commit -m "<reason>"`, not the auto-commit sweep.
- **The `pr-body-vs-diff` check is intentionally lenient (50% threshold).** A stricter check (100% match) would block legitimate PRs that mention sibling files for context. The threshold is tunable in the script — start at 50%, adjust based on false-positive rate.
- **`actions/checkout@v4.3.1` SHA-pin must match the repo's existing pin.** Use `34e114876b0b11c390a56381ad16ebd13914f8d5` per `ci.yml:16`. Floating versions are not allowed.
- **The synthetic-violation test branch must NOT use the `confirm:claude-config-change` label.** That label is the opt-out path; using it on the synthetic test would defeat the verification.
- **The `auto-commit-message-density` regex must NOT match the squash-merge title.** Squash merges produce a single commit on main with the PR title — that commit is the *result*, not a per-commit input to this check. The check runs against `gh pr view --json commits` (per-commit headlines on the PR branch), not against the merge commit on main.
- **Avoid `--rebase` on the auto-pull.** `session-sync.ts:217` already uses `--no-rebase --autostash` — keep that. Rebase on shallow clones produces inconsistent state.
- **The `lint-rule-ids.py` hook will reject the new rule ID if it appears in `scripts/retired-rule-ids.txt`.** Verify before adding: `grep -E '^hr-never-git-add-A' scripts/retired-rule-ids.txt` returns nothing.

## Estimated Effort

- Phase 1 (root cause): ~90 min (TDD, mock surface)
- Phase 2 (.gitignore): ~5 min
- Phase 3 (CI guards): ~120 min (3 bash scripts + 1 workflow + dry-run on this PR)
- Phase 4 (AGENTS.md rule): ~10 min
- Phase 5 (synthetic verification): ~30 min
- Phase 6 (compound + ship): ~30 min

**Total:** ~5 hours single-session.

## Related

- #2857 (closed — bot-authored, settings wipe + diff/description mismatch)
- #2859 (closed — bot-authored, settings wipe + gitlink + diff/description mismatch)
- #2904 (clean human-authored replacement)
- #2815 (bare-repo bot-override learning) — sibling failure mode in the bare-repo identity surface
- AGENTS.md `hr-never-fake-git-author` — directly adjacent rule
- `apps/web-platform/server/session-sync.ts` — root cause file
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:ensure_worktree_identity` — sibling defense pattern
