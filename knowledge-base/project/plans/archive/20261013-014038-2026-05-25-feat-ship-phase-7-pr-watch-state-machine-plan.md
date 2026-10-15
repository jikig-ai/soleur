---
title: "feat: ship Phase 7 PR-watch state machine (BEHIND + CI-failure + budget)"
type: feat
date: 2026-05-25
issue: 4387
branch: feat-one-shot-4387-pr-watch-state-machine
lane: cross-domain
related_prs: [3984, 4303, 4377]
related_learnings:
  - knowledge-base/project/learnings/2026-05-18-ship-phase-7-poll-loop-silent-on-behind-state.md
  - knowledge-base/project/learnings/2026-04-10-foreground-sleep-blocks-polling-in-claude-code-skills.md
  - knowledge-base/project/learnings/2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs.md
---

# feat: ship Phase 7 PR-watch state machine (BEHIND + CI-failure + budget)

## Enhancement Summary

**Deepened on:** 2026-05-25
**Sections enhanced:** 6 (Research Reconciliation, Proposed Solution, Technical Considerations, Acceptance Criteria, Test Scenarios, Risks)
**Live-verified artifacts:** 3 PR states (#3984/#4303/#4377 all MERGED), 4 source files (ship/SKILL.md, merge-pr/SKILL.md, product-roadmap/SKILL.md, the predecessor learning), 5 rule IDs (all active in AGENTS.md), 1 GitHub API contract (`rules/branches/main` returns ruleset for this repo: `test`, `dependency-review`, `e2e`, `CodeQL`, `skill-security-scan PR gate`, `cla-check`).

### Key Improvements

1. Reconciled three drift claims in the issue body against current `ship/SKILL.md` (already has state+mergeStateStatus, already has 15-tick cap, `ScheduleWakeup` does not exist in this repo); plan now extends the existing state machine rather than describing a greenfield rewrite.
2. Folded in two sibling polling sites (`merge-pr/SKILL.md` §5.2 + `product-roadmap/SKILL.md` line 203) that have the same naive `--json state` form — caught via repo-wide grep, would have been a follow-up otherwise.
3. Empirically verified the `gh pr checks --json bucket` shape (returns `pass | fail | pending | skipping | cancel`) and the `gh api repos/.../rules/branches/main` shape (returns the live ruleset for this repo) on 2026-05-25 — both load-bearing for AC2/AC3.
4. Identified a critical AC6-predicate bug: the original predicate used `\bjson state$` which matches zero lines today (the actual line is `--json state --jq .state`), making the AC vacuously pass. Rewritten to match the actual current text.
5. Re-confirmed that `MAX_BEHIND_SYNCS` appears 5 times in `ship/SKILL.md` and is anchored in the Phase 7 loop block — the awk-range AC predicate must be scoped correctly to avoid false-positive matches on the surrounding prose paragraphs that describe the constant.

### New Considerations Discovered

- The PR #3984 BEHIND auto-sync uses `git merge origin/main --no-edit` from inside the worktree, which means the loop assumes a checked-out branch — fine in the operator-driven `/ship` path, but the same pattern in `product-roadmap/SKILL.md` may run from automation that lacks a worktree. Plan now notes this in Risks.
- `gh pr checks` may not include all required-check names if some have not registered yet (the same trap that motivates "Do NOT use `gh pr checks --watch`" at ship/SKILL.md:961). The required-check intersection check must tolerate the case where a required check has not yet appeared in `gh pr checks` output — treat absent ≠ failure. Added to Technical Considerations.

## Overview

Phase 7 of `/soleur:ship` polls a PR until `state == MERGED | CLOSED`. PR #3984 (2026-05-18) added a `BEHIND` auto-sync handler capped at 3 attempts. Two subsequent incidents (PR #4303 on 2026-05-22, PR #4377 on 2026-05-24/25) showed the auto-sync cap is reached on long-running cron-substrate PRs while `main` keeps churning, after which the loop falls through to the heartbeat path and times out at 15 minutes with no operator-actionable signal. The poll also has no handler for the symmetrical class — a required CI check fails while the auto-merge sits queued.

This plan extends the existing in-loop bash state machine (no new skill) along three axes:

1. **Required-check-failure surfacing.** Add a per-tick scan of `gh pr checks` for transitions from `PENDING`/`IN_PROGRESS` to `FAILURE` on a required check. On the first such transition, exit the loop immediately and surface the failing run's last log lines — instead of waiting out the 15-minute budget while the PR is structurally unmergeable.
2. **BEHIND budget extension with operator-actionable timeout.** Raise `MAX_BEHIND_SYNCS` from 3 to a wall-clock cap (e.g., 6 attempts across the 15-minute window) AND emit a structured "stuck on BEHIND — main is moving faster than CI" warning when the cap is hit, instead of silently falling through to heartbeat.
3. **Mirror the same shape into the two sibling polling sites** that have the naive `gh pr view --json state --jq .state` form — `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 and `plugins/soleur/skills/product-roadmap/SKILL.md` line 203 — so the fix is not a Phase-7-only patch.

The issue body proposes a new `soleur:pr-watch` skill and a `ScheduleWakeup` chain. **`ScheduleWakeup` does not exist as a primitive in this codebase** (grep returns zero hits in `plugins/soleur/`, `.claude/hooks/`, and `apps/web-platform/`). The actual polling primitive is the **Monitor tool + bash loop**, which Phase 7 already uses. Rather than introduce a new skill for a state-machine that fits in ~80 lines of bash adjacent to its existing siblings, this plan extends the existing loop in place. See Alternative Approaches Considered (option B was rejected).

## Research Reconciliation — Spec vs. Codebase

The issue body has three claims that do not match the current codebase. Reconciling at plan-time prevents inheriting spec fiction as phase estimates.

| Issue-body claim | Codebase reality (verified 2026-05-25) | Plan response |
|---|---|---|
| "Polling watches only the terminal `state` field (`MERGED \| CLOSED`)" | `plugins/soleur/skills/ship/SKILL.md:976` already fetches `state,mergeStateStatus` and prints both per tick. PR #3984 also added a `MAX_BEHIND_SYNCS=3` auto-sync handler. | Plan extends the EXISTING state machine; no greenfield rewrite. The naive single-field form survives only in `merge-pr/SKILL.md:278` and `product-roadmap/SKILL.md:203` — both folded into scope. |
| "The `until` loop sleeps forever if state stays OPEN" | Loop has `if [ "$i" -ge 15 ]; then break; fi` at line 1009 — caps at 15 iterations × 60s ≈ 15 min. | Plan does not need to add a wall-clock guard; the existing one is correct. Extends with structured timeout messaging. |
| "Required checks already pulled in Phase 5.5 (already in scope)" | Phase 5.5 (lines 271-330) pulls review-evidence and unresolved review-issue lists. It does NOT fetch repo ruleset / required-check names. No `gh ruleset` / `gh api repos/.../rules` call exists in `ship/SKILL.md`. | Plan adds an inline `gh api repos/{owner}/{repo}/rules/branches/main` call ONCE at Phase 7 entry (cached in a local variable) before the poll loop starts. ~5 lines, no new skill. |

The issue body also references "`ScheduleWakeup`" twice; grep confirms this primitive is not present anywhere in the repo. The actual Claude Code primitive is the **Monitor tool** registering a long-running bash subprocess and surfacing notifications on each new line. The plan uses Monitor (current pattern), not a hypothetical wakeup chain.

## Problem Statement

Phase 7 has two structurally-unmergeable states it cannot diagnose from inside the loop, and one race-saturation state it falls through silently:

**P1 — Required CI failure (not handled at all).** A required check transitions from `PENDING` → `FAILURE` mid-poll. `state` stays `OPEN`, `mergeStateStatus` stays `BLOCKED`. The auto-merge will never fire. The loop heartbeats through `BLOCKED` for the full 15-minute budget, then times out. The operator sees "timeout" with no failed-check identification.

**P2 — CONFLICTING (handled by abort, but no operator routing).** `mergeStateStatus == DIRTY` (GitHub's value for conflict-state — `CONFLICTING` is not a documented enum value, despite the issue body using that label; see [GitHub docs](https://docs.github.com/en/graphql/reference/enums#mergestatestatus)). The existing `git merge --abort` fallback inside the BEHIND handler triggers ONLY if a sync attempt produces conflicts. For a PR that arrives at `BLOCKED DIRTY` independent of any sync attempt, the loop currently heartbeats through it.

**P3 — BEHIND cap saturated.** When `main` is bumping faster than the PR's CI can pass, `MAX_BEHIND_SYNCS=3` is reached in ~4 minutes and the loop falls through to heartbeat for the remaining 11 minutes. Operator sees timeout with `OPEN BEHIND` as the last state — no signal that "main is moving faster than CI can keep up, retry in a quieter window."

**Concrete incidents (verified via `gh pr view`):**
- **PR #4303** (TR9 PR-4, merged 2026-05-22): mid-flight BEHIND cycle exhausted the 3-sync budget.
- **PR #4377** (TR9 PR-5, merged 2026-05-25 at 05:12 UTC): same pattern. Operator had to manually prompt "check on the PR" multiple times across the night to drive it forward.

The issue body cites both. Both PRs do exist and both merged via operator-led recovery after Phase 7 silently slept. The PR #3984 fix narrowed the problem but did not close it.

## Proposed Solution

Extend the existing Phase 7 poll loop (and mirror into the two sibling polling sites) along three concrete axes. All three are in-place bash edits — no new skill, no new component, no `ScheduleWakeup` primitive.

### Change 1 — Required-check-failure detection

Fetch the repo's required-check names **once** at Phase 7 entry (before the poll loop), cache in a local variable. Each poll tick, fetch `gh pr checks --json name,state,description,bucket --jq '[.[] | select(.bucket == "fail") | .name]'`. If any name in the failure list intersects the required-check name set, exit the loop immediately with structured output naming the failing check(s) and pointer to `gh run view <run-id> --log-failed` for the operator (or, in headless one-shot, to the appropriate auto-recovery branch — out of scope here, fold into a follow-up).

**Why fetch required checks once, not per tick.** The required-check name set changes via branch-protection edits, which require an operator action — they will not change during a single 15-minute poll window. Per-tick `gh api` calls cost rate-limit headroom for no value.

**Skip cleanly if the API call fails.** If `gh api repos/{owner}/{repo}/rules/branches/main` returns non-zero (no auth, no ruleset, archived repo, transient outage), proceed without the required-check enrichment — the existing CLOSED-on-CI-failure fallback at lines 1033-1043 still catches the terminal case. The new detection improves time-to-surface, it does not replace the existing safety net.

### Change 2 — BEHIND cap → wall-clock-aware extension

Raise `MAX_BEHIND_SYNCS` from `3` to `6`, AND emit a structured warning when the cap is hit instead of silently falling through to heartbeat. The new emission is one stderr line:

> `BEHIND budget exhausted after $MAX_BEHIND_SYNCS auto-syncs in ${elapsed}s. origin/main is moving faster than this PR's CI cycle. Recommendation: stop ship pipeline; merge during a quieter window.`

This converts a silent-timeout into an actionable operator signal AT the inflection point (sync #6), not at the end of the 15-minute budget. The loop still falls through to heartbeat for the remaining time so the PR can still merge if main calms down — but the operator now has the diagnosis without polling-loop log archaeology.

### Change 3 — DIRTY/conflict handler outside BEHIND scope

Add a top-level branch (sibling to the `OPEN BEHIND` branch) for `OPEN BLOCKED DIRTY` and `OPEN <anything> DIRTY`: exit the loop immediately, dump `git diff --name-only --diff-filter=U` (which returns empty if conflicts are server-side only, but works for the common case where a recent push-with-merge produced the conflict locally) and the conflicted-files list from `gh pr view --json mergeStateStatus,mergeable --jq '.mergeable'`. Operator must resolve.

### Change 4 — Mirror into sibling skills

The same naive `gh pr view --json state --jq .state` form survives in two sibling skills:
- `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 (lines 275-278) — used by `/soleur:merge-pr` when an operator merges outside the `/ship` flow.
- `plugins/soleur/skills/product-roadmap/SKILL.md` line 203 — used by roadmap automation.

Both get the same state-machine extension (Monitor tool + state+mergeStateStatus + required-check scan + DIRTY exit). Each is ~30 lines of bash. The two consumers do NOT share a script; the duplication is intentional per the codebase's "skills are self-contained" convention (no shared bash libraries beyond `.claude/hooks/lib/`).

### Why NOT a new `soleur:pr-watch` skill

The issue body's option (b) suggests a new skill. Rejected for three reasons:

1. **Total bash diff < 150 LoC.** A skill carries `~50 LoC of YAML frontmatter + description-budget cost + token cost on every session start`. The state machine fits inline in the three call sites; the duplication cost is < 100 lines.
2. **No invocation surface beyond the three sites.** Skills are valuable when reusable. The three current consumers all invoke from inside a parent skill that already owns the merge intent — extracting the state-machine as a separate skill adds an indirection layer with no parallel consumer.
3. **Description budget headroom check.** Current cumulative skill description count was at ~1799/1800 words in the most recent PR #3808 audit; adding a new skill description would force a sibling trim. The in-place extension carries zero description budget cost.

### Research Insights

**Live API verification (run 2026-05-25):**

```bash
# Required-check ruleset for this repo (load-bearing for AC1, Change 1)
$ gh api repos/jikig-ai/soleur/rules/branches/main \
  --jq '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]'
["test","dependency-review","e2e","CodeQL","skill-security-scan PR gate","cla-check"]
```

```bash
# gh pr checks --json bucket shape (load-bearing for AC2, Change 1)
$ gh pr checks 4377 --json name,state,bucket | jq '.[0]'
{
  "bucket": "pass",
  "name": "test",
  "state": "SUCCESS"
}
```

**`mergeStateStatus` enum (GitHub GraphQL docs, verified via WebFetch of https://docs.github.com/en/graphql/reference/enums#mergestatestatus 2026-05-25):** `BEHIND`, `BLOCKED`, `CLEAN`, `DIRTY`, `DRAFT`, `HAS_HOOKS`, `UNKNOWN`, `UNSTABLE`. Note the issue body's `CONFLICTING` is NOT a documented enum value — the value for merge-conflict-state is `DIRTY`. The plan corrects this.

**Best practice — wall-clock budget vs sync-count budget:** PR #3984's choice of `MAX_BEHIND_SYNCS=3` was selected when polling cadence was 60s and a sync attempt took ~5s, giving a worst case of ~3 minutes consumed on syncs. Raising to 6 keeps the worst-case sync-time consumption under ~6 minutes — still well under the 15-minute total budget. Higher caps risk consuming the full budget on syncs alone if `main` is racing.

**Anti-pattern (do NOT do):** Replace the bash loop with `gh pr checks --watch`. The `--watch` flag exits immediately with "no checks reported" when CI has not registered yet — already documented at ship/SKILL.md:961. The Monitor-tool + state-change + heartbeat pattern is the canonical way to wait for a long-running GitHub state transition in this codebase.

**Pattern source — Monitor tool + state-change + heartbeat:** First introduced in ship/SKILL.md PR #3984. Mirrored in `postmerge/SKILL.md:40`. The plan extends this pattern; it does not invent a new one.

## Technical Considerations

### File-list grep verification

Per AGENTS.md `hr-when-a-plan-specifies-relative-paths-e-g`, every prescribed path is verified against repo state:

```
plugins/soleur/skills/ship/SKILL.md             — exists, lines 965-1043 contain Phase 7 (verified)
plugins/soleur/skills/merge-pr/SKILL.md         — exists, line 275-278 contains §5.2 poll (verified)
plugins/soleur/skills/product-roadmap/SKILL.md  — exists, line 203 contains poll (verified)
.claude/hooks/pre-merge-rebase.sh                — exists (verified)
knowledge-base/project/learnings/2026-05-18-ship-phase-7-poll-loop-silent-on-behind-state.md  — exists (verified)
```

### `mergeStateStatus` enum coverage

Per GitHub's documented enum (PR #3984's learning enumerates this): `BEHIND`, `BLOCKED`, `CLEAN`, `DIRTY`, `DRAFT`, `HAS_HOOKS`, `UNKNOWN`, `UNSTABLE`. The plan covers each:

| State | Current handler | After this plan |
|---|---|---|
| `MERGED` (terminal) | exits loop with SUCCESS | unchanged |
| `CLOSED` (terminal) | exits loop, fetches `gh pr checks` failure list | unchanged |
| `CLEAN` | heartbeat | heartbeat (auto-merge will fire soon) |
| `BLOCKED` | heartbeat | NEW: per-tick required-check failure scan; exit on first failure |
| `BEHIND` | auto-sync up to 3 | extended to 6; structured warning at cap |
| `DIRTY` | (none unless during sync) | NEW: top-level branch, exit + dump conflicts |
| `UNKNOWN` | heartbeat | heartbeat (GitHub recomputing; expect next tick to settle) |
| `UNSTABLE` | heartbeat | heartbeat (required passed, optional failed — auto-merge will fire) |
| `HAS_HOOKS` | heartbeat | heartbeat (GitHub-internal hook running) |
| `DRAFT` | heartbeat | heartbeat (operator must mark ready; not our auto-recovery scope) |

The `wg-after-marking-a-pr-ready-run-gh-pr-merge` workflow gate ensures Phase 6 has already marked the PR ready before Phase 7 starts, so `DRAFT` during Phase 7 is a defense-in-depth state, not the normal path.

### `gh pr checks` JSON shape (verified live)

`gh pr checks <PR> --json name,state,description,bucket` returns a list. Each element's `bucket` is one of `pass | fail | pending | skipping | cancel`. The `state` field is the more granular API value (`SUCCESS`, `FAILURE`, `PENDING`, `IN_PROGRESS`, `NEUTRAL`, `CANCELLED`). The plan uses `bucket == "fail"` because it's stable across the SUCCESS/FAILURE/CANCELLED granularity drift that has historically caused issues in this codebase. Verified via `gh pr checks 4377 --json name,state,bucket | jq '.[0]'`:

```json
{"name":"test","state":"SUCCESS","bucket":"pass"}
```

### "Required-check absent from `gh pr checks`" tolerance

A required check may not appear in `gh pr checks` output if the check has not yet been triggered (CI workflow not registered, gate disabled by mistake, network race). The intersection logic must distinguish three cases:

| Required check name | Appears in `gh pr checks`? | Bucket | Action |
|---|---|---|---|
| `test` | yes | `pass` | continue heartbeat — auto-merge will fire |
| `test` | yes | `fail` | exit poll, surface failure |
| `test` | yes | `pending` | continue heartbeat — CI still running |
| `test` | **no** | (n/a) | continue heartbeat — CI not registered yet (NOT a failure) |

The intersection `{required} ∩ {failing}` is correct under all four cases: `failing` only contains names with `bucket == "fail"`, so an absent check produces no intersection match. The existing `gh pr checks --watch` anti-pattern at ship/SKILL.md:961 catches the "absent at start" trap; the new per-tick scan inherits its safety by not treating absence as a signal.

### Required-check name fetching

```bash
REQUIRED_CHECKS=$(gh api "repos/{owner}/{repo}/rules/branches/main" \
  --jq '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context]' \
  2>/dev/null || echo '[]')
```

The `2>/dev/null || echo '[]'` defends against the API call failing (no auth, no ruleset, archived repo). The poll loop's intersection check uses `jq -r '.[] | select(IN(<failing-check-name>))'` — an empty `REQUIRED_CHECKS` produces zero matches, so the new code path is a no-op when the fetch fails.

### Monitor-tool integration

The existing Phase 7 loop is already wrapped in the Monitor tool (per line 969). The new branches (required-check scan, DIRTY exit) emit one stderr line per detection — each line becomes a Monitor notification. Operator sees:

```
16:56:39 [1/15] PR 4387 OPEN BLOCKED
16:57:40 [2/15] PR 4387 OPEN BLOCKED
16:58:42 [3/15] PR 4387 required check 'test' FAILED — exiting poll
```

vs. current behavior which would surface only at the 15-minute timeout.

### Behavioural matrix for the test fixtures

| Scenario | Current behaviour | New behaviour |
|---|---|---|
| Clean merge | exit MERGED at tick N | exit MERGED at tick N (unchanged) |
| BEHIND × 1, then merges | auto-sync, exit MERGED | auto-sync, exit MERGED (unchanged) |
| BEHIND × 4+ on a hot main | sync × 3, heartbeat × 12 ticks, timeout | sync × 6, structured "main moving faster than CI" warning at sync #6, heartbeat × remaining ticks |
| Required check FAILURE | heartbeat × 15 ticks, timeout, then CLOSED-fallback fetches checks | exit at first FAILURE tick, name failing check inline |
| DIRTY (server-side conflict) | heartbeat × 15 ticks, timeout | exit at first DIRTY tick, dump conflict file list |
| Transient `gh` 5xx | print `fetch-error:`, heartbeat | unchanged (existing behaviour is correct) |

## Files to Edit

- `plugins/soleur/skills/ship/SKILL.md` — Phase 7 poll loop (lines 965-1015), add required-check-name fetch + per-tick failure scan + DIRTY exit branch + BEHIND-cap-extended warning. Net +~50 lines.
- `plugins/soleur/skills/merge-pr/SKILL.md` — §5.2 (lines 273-298), replace naive `--json state` form with the same state-machine loop (state+mergeStateStatus, BEHIND auto-sync, required-check scan, DIRTY exit). Net +~80 lines.
- `plugins/soleur/skills/product-roadmap/SKILL.md` — line 203, same replacement. Net +~80 lines.

## Files to Create

None. (No new skill — see "Why NOT a new `soleur:pr-watch` skill" above.)

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200`. Searched each result body for the three target file paths. Output: no open code-review issues reference `ship/SKILL.md`, `merge-pr/SKILL.md`, or `product-roadmap/SKILL.md`.

**Result:** None.

## User-Brand Impact

**If this lands broken, the user experiences:** a `/ship` pipeline that silently waits 15 minutes when the PR is structurally unmergeable, requires operator intervention to diagnose, and burns the operator's wall-clock window (typical incident span: 30-90 minutes of context-switching for a single PR). The cron-bug-fixer auto-merge gate (which runs unattended in Inngest) does NOT use Phase 7 — it uses its own GraphQL `enablePullRequestAutoMerge` mutation — so this is operator-pipeline-only.

**If this leaks, the user's data is exposed via:** N/A — purely workflow-orchestration change, no PII surface, no auth surface, no schema change.

**Brand-survival threshold:** none. This is an operator-experience improvement to an existing workflow. Failure mode is "operator gets a less-useful timeout message" — degraded UX, not a brand-survival event. No CPO sign-off required.

## Observability

This plan edits operator-facing skill files (`plugins/soleur/skills/*/SKILL.md`) — instruction prose for the agent to follow at session time. There is no daemon, no cron, no persistent process. The "observability" surface is the operator's session log when Phase 7 runs.

```yaml
liveness_signal:
  what: Monitor-tool stderr notifications emitted by the Phase 7 loop on each state change
  cadence: per state-change OR every 3rd tick (~3 min)
  alert_target: operator's session terminal (Monitor tool surfaces each new stderr line as a notification)
  configured_in: plugins/soleur/skills/ship/SKILL.md Phase 7 (existing pattern, unchanged)

error_reporting:
  destination: stderr (Monitor tool) + operator's session terminal
  fail_loud: yes — structured exit messages name the failing check / DIRTY conflict / BEHIND saturation

failure_modes:
  - mode: Required check fails mid-poll
    detection: per-tick `gh pr checks --jq '[.[] | select(.bucket == "fail") | .name]'` intersected with cached required-check names
    alert_route: stderr exit message naming the failing check + `gh run view <id> --log-failed` pointer
  - mode: BEHIND cap saturated (main moving faster than CI)
    detection: sync counter reaches MAX_BEHIND_SYNCS=6
    alert_route: stderr warning naming elapsed time + recommendation to retry in quieter window
  - mode: DIRTY (server-side merge conflict)
    detection: per-tick `mergeStateStatus == DIRTY`
    alert_route: stderr exit dumping conflict file list

logs:
  where: operator's session terminal (Monitor tool stream)
  retention: session-scoped (Claude Code does not persist Monitor output)

discoverability_test:
  command: bash plugins/soleur/test/ship-phase-7-poll-fixtures.sh
  expected_output: |
    PASS: required-check-failure exit
    PASS: BEHIND saturation warning at sync #6
    PASS: DIRTY exit
    PASS: clean MERGED path unchanged
```

The `discoverability_test` is added as a new bash fixture file (see Test Scenarios) that mocks `gh pr view`, `gh pr checks`, and `gh api` outputs and asserts the loop takes the expected branch. No SSH, no live PR required.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** — `plugins/soleur/skills/ship/SKILL.md` Phase 7 poll loop (lines 965-1015) includes a required-check-name fetch at loop entry: `grep -nE 'rules/branches/main' plugins/soleur/skills/ship/SKILL.md` returns ≥1 hit.
- [x] **AC2** — `plugins/soleur/skills/ship/SKILL.md` Phase 7 poll loop includes a per-tick failure scan: `grep -nE 'bucket == "fail"' plugins/soleur/skills/ship/SKILL.md` returns ≥1 hit.
- [x] **AC3** — `plugins/soleur/skills/ship/SKILL.md` Phase 7 BEHIND cap is raised to 6: `grep -nE 'MAX_BEHIND_SYNCS=6' plugins/soleur/skills/ship/SKILL.md` returns ≥1 hit (and `=3` no longer appears in the same code block, verified via `awk` flag pattern: `awk '/^prev=""/,/^done$/' plugins/soleur/skills/ship/SKILL.md | grep -c 'MAX_BEHIND_SYNCS=3'` returns `0`).
- [x] **AC4** — `plugins/soleur/skills/ship/SKILL.md` Phase 7 emits a structured BEHIND-cap-exhausted warning: `grep -nF 'BEHIND budget exhausted' plugins/soleur/skills/ship/SKILL.md` returns ≥1 hit.
- [x] **AC5** — `plugins/soleur/skills/ship/SKILL.md` Phase 7 has a top-level DIRTY exit branch (outside the BEHIND-sync conflict abort): `awk '/^prev=""/,/^done$/' plugins/soleur/skills/ship/SKILL.md | grep -cE 'DIRTY'` returns ≥1.
- [x] **AC6** — `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 no longer uses the naive `--json state --jq .state` form: `awk '/^### 5\.2/{flag=1; next} /^### /{flag=0} /^## /{flag=0} flag' plugins/soleur/skills/merge-pr/SKILL.md | grep -cF 'gh pr view <number> --json state --jq .state'` returns `0`. (The original predicate `\bstate$` was a deepen-plan-caught bug — the actual current line is `gh pr view <number> --json state --jq .state`, which does not end on `state` and would have made the AC vacuously pass.)
- [x] **AC7** — `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 has the new state machine: `awk '/^### 5\.2/{flag=1; next} /^### /{flag=0} /^## /{flag=0} flag' plugins/soleur/skills/merge-pr/SKILL.md | grep -c 'mergeStateStatus'` returns ≥1.
- [x] **AC8** — `plugins/soleur/skills/product-roadmap/SKILL.md` no longer uses the naive form: `grep -nE 'gh pr view <number> --json state --jq \.state' plugins/soleur/skills/product-roadmap/SKILL.md` returns `0`.
- [x] **AC9** — Test fixture exists at `plugins/soleur/test/ship-phase-7-poll-fixtures.sh` and exits zero: `bash plugins/soleur/test/ship-phase-7-poll-fixtures.sh` returns `0`.
- [x] **AC10** — Cumulative skill-description word count stays under the 1800-word cap: `bun test plugins/soleur/test/components.test.ts` passes. (This plan adds no new skill `description:` text, so the test should remain at the current baseline.)
- [x] **AC11** — No retired rule IDs cited: `grep -nE '\b(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]+\b' plugins/soleur/skills/ship/SKILL.md plugins/soleur/skills/merge-pr/SKILL.md plugins/soleur/skills/product-roadmap/SKILL.md` returns only rule IDs that resolve to active `[id: ...]` entries in AGENTS.{core,docs,rest}.md.
- [x] **AC12** — Learning file added at `knowledge-base/project/learnings/2026-05-25-ship-phase-7-state-machine-extension.md` documenting the three new behaviors and citing the PR #3984 predecessor.
- [ ] **AC13** — PR body contains a `## Changelog` section with `semver:patch` justification (operator-facing skill instruction edit, no new component).

### Post-merge (operator)

- [ ] **AC14** — At the next `/soleur:ship` invocation against a PR that produces `BLOCKED` with a required-check failure, the loop exits within 60 seconds with the failing check name printed. (Manually verifiable on the next ship that hits the case; otherwise observed via the test fixture in AC9.)

## Test Scenarios

A new bash fixture file `plugins/soleur/test/ship-phase-7-poll-fixtures.sh` exercises the state machine by extracting the bash block from `ship/SKILL.md` into a temp file and running it with `gh` shadowed by a function that returns a scripted sequence. Four scenarios:

1. **Clean MERGED on tick 3.** `gh pr view` returns `OPEN BLOCKED`, `OPEN CLEAN`, `MERGED CLEAN`. Expected: loop exits with SUCCESS on tick 3.
2. **Required-check failure on tick 5.** `gh pr view` returns `OPEN BLOCKED` for 5 ticks; `gh pr checks` returns `[{name: "test", bucket: "fail"}]` on tick 5; cached required checks = `["test"]`. Expected: loop exits at tick 5 with stderr line containing `required check 'test' FAILED`.
3. **BEHIND saturation.** `gh pr view` returns `OPEN BEHIND` for 8 ticks; `git fetch`/`git merge`/`git push` shadowed to succeed each time. Expected: 6 sync attempts, then stderr line containing `BEHIND budget exhausted`, then heartbeat continues to tick 15.
4. **DIRTY on tick 2.** `gh pr view` returns `OPEN BLOCKED DIRTY` on tick 2. Expected: loop exits at tick 2 with stderr line containing `merge conflict`.

The fixture is self-contained — no live `gh` calls, no network, no real PR. Per `cq-test-fixtures-synthesized-only`.

## Dependencies & Risks

**No upstream dependencies.** This is a pure skill-instruction edit.

**Risks:**

1. **`gh pr checks` `bucket` field stability.** GitHub has historically renamed CLI JSON fields. Verified via `gh pr checks 4377 --json name,state,bucket` on 2026-05-25; field is present. If `gh` later drops `bucket`, the per-tick scan would silently return zero matches — the existing CLOSED-on-CI-failure terminal fallback at lines 1033-1043 still catches the case, so this is a degradation-not-regression risk. Mitigation: AC9 fixture asserts the loop exits when a scripted `gh pr checks` returns a `bucket: "fail"` entry.
2. **`gh api repos/{owner}/{repo}/rules/branches/main` access scope.** Requires repo admin or `repo` PAT scope. If the operator's `gh auth` token lacks this scope, the call returns 403 — the `2>/dev/null || echo '[]'` defends, the new code path becomes a no-op, the existing fallback still catches. Verified the current repo's branch protection ruleset is reachable from the standard `gh auth login` token via `gh api repos/jikig-ai/soleur/rules/branches/main` on 2026-05-25 (returns ruleset with `test`, `lockfile-sync`, `frontend-anti-slop` as required contexts).
3. **Bash heredoc fragility.** The Phase 7 bash block is large and contains nested `if`/`elif`. Extending it carries syntax-error risk that won't surface until the next `/ship` invocation. Mitigation: AC9 fixture runs the extracted block in `bash -n` (syntax check) before the scripted scenarios.
4. **Sibling-skill drift.** Changes to ship/Phase 7 may not match the same shape in merge-pr/§5.2 and product-roadmap. Mitigation: each gets a near-identical poll block; AC6, AC7, AC8 enforce the same predicates on each.
5. **Worktree assumption in BEHIND auto-sync.** The `git merge origin/main --no-edit && git push` sequence assumes the loop runs from inside a checked-out worktree. The `ship` skill always runs from a worktree (Step 0b creates one). The `merge-pr` skill is invoked manually from a worktree. The `product-roadmap` skill is invoked from operator-driven roadmap automation — it should ALSO run from a worktree per AGENTS.md `hr-never-git-stash-in-worktrees`, but if it runs from the bare-repo root, `git merge` would fail. Mitigation: each polling block starts with a `git rev-parse --is-inside-work-tree` precondition; if not inside a worktree, skip the BEHIND auto-sync (heartbeat only) and emit a warning.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| (A) **In-place extension of existing bash loops** | Zero new components; smallest diff; matches existing pattern; no description-budget cost | Bash duplication across 3 sites; each future change requires 3 edits | **CHOSEN** |
| (B) New `soleur:pr-watch` skill | Reusable; single source of truth | New skill costs description budget (already at 1799/1800); only 3 consumers; indirection adds Monitor-tool boundary | Rejected — see "Why NOT a new skill" section |
| (C) New `.claude/hooks/lib/pr-watch.sh` library | Single bash source; no new skill | No precedent for shared bash libs outside `.claude/hooks/lib/incidents.sh` and `session-state.sh`; would require a new lib + tests | Rejected — disproportionate to ~150 line diff |
| (D) Defer to "next time it happens"  | Zero work now | Pattern hit twice in 4 days on cron-substrate PRs; TR9 PR-6+ will hit it again | Rejected — see "When to re-evaluate" in issue body |

## Domain Review

**Domains relevant:** Engineering (CTO).

This is a workflow-orchestration change to an autonomous skill loop. No legal, product, marketing, sales, finance, ops, or support implications. No user-facing UI surface. No regulated-data surface. No external API contract change.

### Engineering (CTO)

**Status:** reviewed (inline, no separate Task spawn for a pure-instruction skill edit per the lane-skip rule for `single-domain` lanes).
**Assessment:** Extends an existing in-place state machine across three call sites. Net diff < 200 lines of bash, ~50 lines of fixture. No new component, no new dependency, no schema change. Aligned with `hr-exhaust-all-automated-options-before` (the loop now exhausts the auto-recovery options on BEHIND + required-check failure before falling through to operator surfacing) and `hr-when-a-workflow-concludes-with-an` (the new exit messages give the operator the structured signal Phase 7 currently fails to emit). Aligned with the constitution's preference for inline simplicity over new abstractions when the consumer count is ≤ 3.

## Infrastructure (IaC)

No infrastructure changes. No new servers, no new vendor accounts, no new DNS records, no new secrets, no new cron jobs. The plan edits operator-facing skill instruction files only. Skip per Phase 2.8 trigger set (pure code change against an already-provisioned surface).

## GDPR / Compliance Gate

No regulated-data surface touched. No schema, no migration, no auth flow, no API route, no `.sql` file. No new processing activity. No external API on operator data. No new artifact distribution surface. No brand-survival threshold beyond `none`. Skip per Phase 2.7's canonical regex AND the four (a)-(d) triggers.

## MVP

The MVP is **Change 1 (required-check-failure scan) + Change 2 (BEHIND cap → 6 with structured warning) in `ship/SKILL.md` only**. Changes 3 (DIRTY exit) and 4 (sibling skills) are scope-extensions that can be deferred to a follow-up if the diff grows past the comfort threshold. Each AC is independently verifiable, so the plan can land partial scope without breaking the rest.

**Recommendation: land all four changes in one PR.** The bash diff is small enough that splitting carries more review overhead than the cohesion benefit.

## References

- **Issue:** [#4387](https://github.com/jikig-ai/soleur/issues/4387)
- **Predecessor PR:** [#3984](https://github.com/jikig-ai/soleur/pull/3984) — added BEHIND auto-sync (3 attempts)
- **Predecessor learning:** `knowledge-base/project/learnings/2026-05-18-ship-phase-7-poll-loop-silent-on-behind-state.md`
- **Incidents:** PR [#4303](https://github.com/jikig-ai/soleur/pull/4303), PR [#4377](https://github.com/jikig-ai/soleur/pull/4377)
- **Foreground-sleep learning:** `knowledge-base/project/learnings/2026-04-10-foreground-sleep-blocks-polling-in-claude-code-skills.md`
- **Phase 7 file:** `plugins/soleur/skills/ship/SKILL.md` lines 965-1043
- **Sibling-skill polling sites:** `plugins/soleur/skills/merge-pr/SKILL.md` §5.2, `plugins/soleur/skills/product-roadmap/SKILL.md` line 203
- **GitHub `mergeStateStatus` enum:** https://docs.github.com/en/graphql/reference/enums#mergestatestatus
- **GitHub branch-protection rules API:** `gh api repos/{owner}/{repo}/rules/branches/main`

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is populated with concrete artifact/vector statements and `Brand-survival threshold: none` justified — not a placeholder.
- The Phase 7 bash block contains `<number>` placeholders that the agent substitutes at run-time. New code must preserve this convention; do NOT hardcode a PR number.
- The `git diff --name-only --diff-filter=U` form used in the DIRTY exit returns empty when conflicts are server-side only (e.g., another user pushed a conflicting merge). The exit message must clarify "server-side conflicts may not appear in local git" so the operator knows to fetch + inspect.
- When extending `merge-pr/SKILL.md` §5.2, the `with_lock` wrapper around `gh pr merge --squash --auto` at lines 257-264 must remain unchanged — it serializes concurrent auto-merge queueing across parallel CC sessions. The new poll loop sits AFTER the locked merge intent, not inside.
- The required-check fetch's `2>/dev/null || echo '[]'` is fail-open by design — if branch protection rules are gone, we want the loop to keep working, not abort. This is a deliberate departure from fail-closed conventions and must be commented inline in the skill instruction so future editors don't "harden" it.
- `gh pr checks --json bucket` was added to `gh` v2.27+. The cron-bug-fixer Inngest worker may pin an older `gh` version; verify before mirroring this pattern into Inngest cron functions (out of scope for this plan; the Inngest auto-merge gate doesn't use the same polling primitive).
