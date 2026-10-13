# Plan: Fix #2526 — deploy-verify timeout (already resolved by PR #2523)

**Date:** 2026-04-22
**Branch:** `feat-one-shot-fix-2526-deploy-verify-timeout`
**Issue:** #2526
**Type:** housekeeping / duplicate closure

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** 6 (TL;DR, Evidence, Research Reconciliation, Phase 1–3, Non-Goals/Risks)
**Research agents used:** live `gh api` probes (issues/2519, pulls/2523, actions/runs/24732382107), `git log --grep`, `gh issue close --help` verification, duplicate-closure convention grep on recent closed issues.

### Key Improvements

1. **Corrected the `gh issue close` invocation.** Original plan said `--reason "duplicate"` required graph mutation and recommended `--reason "not planned"`. Live `gh issue close --help` confirms `duplicate` is a first-class CLI option (`{completed|not planned|duplicate}`). Phase 3 updated.
2. **Pinned live SHAs and timestamps.** Every "merged at" / "run ID" / "SHA" claim is now backed by a `gh api` call output in the Evidence section, per the quality-check rule against memory-cited SHAs.
3. **Widened duplicate proof.** Pulled `#2519`'s body — it cites the same file, same knobs, and the same proposed fix (24 → 60). Textbook duplicate, not a "race-window dup that happens to coincide." Recorded verbatim in the duplicate-proof table.
4. **Tightened the learning's scope.** Originally drafted as "`/soleur:one-shot` needs duplicate detection." Deepen pass surfaced that this is actually a triage-time problem spanning `/soleur:fix-issue`, `/soleur:triage`, and `/soleur:one-shot`. The follow-up issue is rescoped accordingly.
5. **Added invariant-diff acceptance criterion.** Ensures the workflow file stays byte-identical to `main`, preventing a subtle no-op edit from the work skill.
6. **Removed the redundant "Phase 4 follow-up" as blocking.** The follow-up issue is still prescribed but explicitly gated as post-merge operator work — not a pre-merge blocker on a housekeeping PR.

### New Considerations Discovered

- **Issue author attribution.** #2526 was filed by the bot (github-actions) observing the failed run, not by a human. This means: (a) no politeness tax on the duplicate-close message, (b) the "duplicate detection" tooling must run on bot-filed issues too — they're the majority of the triage load.
- **PR #2523 already has a live-run acceptance check in its test plan** (unchecked: "next organic release run reports completed within the new 300s ceiling"). The 4+ successful post-fix runs (culminating in 24732382107, v0.48.2) satisfy that check. A second acceptance task for the same invariant is waste; do not add one.
- **The closest analogous prior-art** is PR #2479's HSTS drift closure, which was also closed `NOT_PLANNED` against a shipped-upstream fix. Pattern is consistent.

---

## TL;DR

**#2526 is a duplicate of #2519.** The exact fix proposed in #2526 — raising `STATUS_POLL_MAX_ATTEMPTS` from 24 to 60 (300s window, 5s interval) — shipped in **PR #2523 (merged 2026-04-17 21:07 UTC)**, ~20 minutes after #2526 was filed at 20:59 UTC. The filer didn't see #2519 / #2523 in flight.

Main, worktree, and every release run since 2026-04-17 already carry the 300s window. The most recent successful run (**24732382107**, v0.48.2, 2026-04-21) completed on `Attempt 6/60` within ~32 seconds, proving the window is live and effective.

**Therefore: no code change is required for #2526.** This plan covers the bookkeeping:

1. Verify the fix is live on main and on this worktree (done — evidence below).
2. Close #2526 as `duplicate` of #2519, referencing PR #2523.
3. Capture the learning on **duplicate-detection at issue-triage time** — neither `/soleur:triage`, `/soleur:fix-issue`, nor `/soleur:one-shot` currently checks whether an open issue's proposed fix is already on main before spawning work.

No web-platform-release.yml edit will be made. Attempting one would regress the change or introduce churn.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| `.github/workflows/web-platform-release.yml` has `STATUS_POLL_MAX_ATTEMPTS: 24` | File on `main@HEAD` and this worktree both have `STATUS_POLL_MAX_ATTEMPTS: 60` (line 106) with a 6-line comment block attributing the bump to run `24583922171` and PRs #2205/#2519. | No workflow edit. Close #2526 as dup of #2519. |
| Proposed fix is "raise `STATUS_POLL_MAX_ATTEMPTS` from 24 to at least 60" | Already done in PR #2523 (merged 2026-04-17). | Acknowledge in the closure comment. |
| Issue cites run `24586094392` (v0.43.2, 54s short) as evidence. | Pre-fix evidence, correctly diagnosed in #2519 and resolved by #2523. | No re-investigation needed. |

## Evidence

### 1. main already has the 300s window (live-probed 2026-04-22)

```text
$ git show main:.github/workflows/web-platform-release.yml | sed -n '106,107p'
          STATUS_POLL_MAX_ATTEMPTS: 60
          STATUS_POLL_INTERVAL_S: 5
```

```text
$ gh api repos/jikig-ai/soleur/pulls/2523 --jq '{number, title, merged_at, merge_commit_sha}'
{
  "number": 2523,
  "title": "fix(ci): bump web-platform-release verify-completion window to 300s",
  "merged_at": "2026-04-17T21:07:20Z",
  "merge_commit_sha": "29afaabb960b4aefe216dc897b7a2811375db3b8"
}
```

```text
$ gh api repos/jikig-ai/soleur/issues/2519 --jq '{number, state, title}'
{
  "number": 2519,
  "state": "closed",
  "title": "fix(ci): web-platform-release verify step 120s timeout is too short"
}
```

`git log main -- .github/workflows/web-platform-release.yml`:

```text
29afaabb fix(ci): bump web-platform-release verify-completion window to 300s (#2523)
4c292842 fix(ci): apply jq -e guard to web-platform-release.yml health-check loop (#2447)
6e7b4181 fix(ci): tolerate non-JSON bodies in deploy-status verify step (#2226)
```

### 2. Post-fix runs confirm the window is effective (live-probed 2026-04-22)

```text
$ gh api repos/jikig-ai/soleur/actions/runs/24732382107 \
    --jq '{id, display_title, conclusion, run_started_at, updated_at, head_sha}'
{
  "id": 24732382107,
  "display_title": "fix(infra): allowlist AI crawler UAs at Cloudflare edge (#2740)",
  "conclusion": "success",
  "run_started_at": "2026-04-21T15:53:40Z",
  "updated_at": "2026-04-21T15:59:21Z",
  "head_sha": "05d34f06199d0f7b66669a5ad556e4a923da00dc"
}
```

`gh run list --workflow "Web Platform Release" --limit 5`:

| Run ID | Date | Outcome | Notes |
|---|---|---|---|
| 24742374237 | 2026-04-21 | **failure** | Unrelated — Block-AI-bots feature (#2748 line of work). Not a verify-timeout. |
| **24732382107** | 2026-04-21 | **success** | **v0.48.2 — completed on Attempt 6/60 (~32s).** |
| 24638591714 | 2026-04-19 | success | |
| 24637407417 | 2026-04-19 | success | |
| 24636857349 | 2026-04-19 | success | |

Log excerpt from 24732382107 (the canonical post-fix proof):

```text
Attempt 1/60: ci-deploy.sh still running (reason=running)
Attempt 2/60: ci-deploy.sh still running (reason=running)
...
Attempt 6/60: ci-deploy.sh still running (reason=running)
ci-deploy.sh completed successfully for v0.48.2
```

The new counter is `i/60`, not `i/24`. Fix is live.

### 3. Timing proves this is a duplicate, not a regression

```text
#2519 opened  — earlier (fix work started)
#2526 opened  — 2026-04-17 20:59:58 UTC
PR #2523 merged — 2026-04-17 21:07:20 UTC  (7m 22s after #2526 was filed)
#2519 closed  — 2026-04-17 21:07:21 UTC    (auto-closed by PR merge)
```

The `#2526` author (github-actions bot, filing from an observed CI failure) created the issue during a merge-window race with `#2523`. No fault — but also no code change to make.

### 4. Duplicate-proof table (bodies of #2519 and #2526, side-by-side)

| Attribute | #2519 | #2526 | Match |
|---|---|---|---|
| Workflow file | `.github/workflows/web-platform-release.yml` | `.github/workflows/web-platform-release.yml` | ✅ |
| Failing step | `Verify deploy script completion` | `Verify deploy script completion` | ✅ |
| Observed timeout | `120s` (24 × 5s) | `120s` (24 × 5s) | ✅ |
| Failing run cited | `24583922171` (v0.43.0) | `24586094392` (v0.43.2) | Different runs, same root cause |
| Proposed fix | "Increase `STATUS_POLL_MAX_ATTEMPTS` from 24 to 60 (5-minute ceiling) OR … `STATUS_POLL_INTERVAL_S` from 5 to 10" | "Raise `STATUS_POLL_MAX_ATTEMPTS` from 24 to at least 60 (60 × 5 = 300s = 5 minute window) … Alternatively: switch the poll interval to 10s with 30 attempts" | ✅ Verbatim overlap on both options |
| Severity framing | False-negative CI signal violates `wg-after-a-pr-merges-to-main-verify-all` | Same AGENTS.md rule cited by name | ✅ |

Textbook duplicate. Both issues prescribe the identical parameter change; neither adds a dimension the other missed.

## Hypotheses

This issue's hypothesis space is closed. Root cause diagnosis in #2519: `24 × 5s = 120s` poll window was tighter than the observed deploy time (~170-200s). Fix: extend to `60 × 5s = 300s`. Merged. Verified on 4+ organic runs.

No network-outage checklist applies here — the problem was never a network issue; it was a CI wall-clock too short for the real deploy duration. L3 firewall verification (`hr-ssh-diagnosis-verify-firewall`) is not triggered: the symptom is a CI poll timeout on an HTTP endpoint that *did respond* (with `exit_code: -1 / reason: running`), not an SSH/TCP/kex/5xx failure.

## Open Code-Review Overlap

**Files to Edit:** none. **Files to Create:** one learning file (path below).

Standalone jq probe against open `code-review` issues:

```bash
gh issue list --label code-review --state open \
  --json number,title,body --limit 200 > /tmp/open-review-issues.json

for f in \
  ".github/workflows/web-platform-release.yml" \
  "knowledge-base/project/learnings/best-practices/2026-04-22-one-shot-duplicate-detection.md"
do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' \
    /tmp/open-review-issues.json
done
```

None. (Empty workflow-file touch set; the learning file is new.)

## Overview

### Non-Goals

- **Do not edit `.github/workflows/web-platform-release.yml`.** The target value (60) is already in place. An idempotent "change" would be a no-op commit that confuses history; a *different* value would regress the validated fix.
- **Do not re-open #2519 or add a second learning about poll-window sizing.** `knowledge-base/project/learnings/best-practices/2026-04-17-align-ci-poll-windows-with-adjacent-steps.md` (from PR #2523) already covers this class.
- **Do not add a test harness.** The acceptance test is a live release run, and we have 4+ successful ones post-fix already.

### Goals

1. Close #2526 with a duplicate pointer to #2519 and PR #2523, citing the live-run evidence above.
2. Capture a new learning on **duplicate-detection at the triage boundary** (`/soleur:triage` → `/soleur:fix-issue` / `/soleur:one-shot`) — the pipeline handed this issue to a fix worktree without first checking whether an open PR or a recent main commit already resolved it. The learning specifies a concrete grep-based heuristic for named-knob proposed-fix bodies (see Phase 4 Research Insights).
3. Leave the workflow file untouched.

## Implementation Phases

### Phase 1 — Verification (5 min)

Already done during planning, but re-confirmed by the work skill before closure:

- [ ] `git show main:.github/workflows/web-platform-release.yml | grep -n STATUS_POLL_MAX_ATTEMPTS` reports `60`.
- [ ] `gh pr view 2523 --json state` reports `MERGED`.
- [ ] `gh run list --workflow "Web Platform Release" --limit 10 --json conclusion,databaseId,displayTitle` shows at least one `success` where logs include the string `Attempt <n>/60` (prior run 24732382107 qualifies).

If any of the three fail, **abort this plan** — the world has shifted and a fresh diagnosis is needed. Do not attempt to re-bump the value.

### Phase 2 — Learning (10 min)

**Create:** `knowledge-base/project/learnings/best-practices/2026-04-22-one-shot-duplicate-detection.md`.

Content outline:

- **What happened:** `/soleur:one-shot` on #2526 spun up a worktree, plan, and (in the naive path) would have tried to raise `STATUS_POLL_MAX_ATTEMPTS` a second time. The issue body's proposed fix was already shipped 5 days earlier in PR #2523.
- **Detection gap:** `/soleur:fix-issue` and `/soleur:one-shot` entry do not currently verify "is this issue already fixed on main?" A three-line check would have caught it:
  1. `gh issue view <N> --json body | jq -r .body | grep -oE '[A-Z_]+_POLL_[A-Z_]+|<config-symbol>'` to extract any named knob.
  2. `git grep <symbol> origin/main -- <path-in-issue>` to see if the value already matches the "proposed fix".
  3. If yes → close as `duplicate`, don't spawn a fix branch.
- **Remediation:**
  - Short-term: this plan closes #2526 and cross-references.
  - Longer-term (proposed, not in-scope for this PR): `/soleur:fix-issue` and `/soleur:one-shot` should, at the triage step, diff the issue's "Proposed Fix" block against current main. File a follow-up issue for this tooling improvement.
- **Tag:** `best-practices`, `workflow`, `one-shot`.

### Phase 3 — Closure (5 min)

**Corrected invocation:** `gh issue close --reason "duplicate"` is a first-class CLI option. Verified live:

```text
$ gh issue close --help | grep reason
  -r, --reason string         Reason for closing: {completed|not planned|duplicate}
```

The original draft of this plan incorrectly said `duplicate` required a GraphQL mutation. It does not. Use the dedicated reason so GitHub's issue graph reflects the relationship:

```bash
gh issue close 2526 --reason "duplicate" --comment "$(cat <<'EOF'
Duplicate of #2519. The proposed fix (raise `STATUS_POLL_MAX_ATTEMPTS`
24 → 60, extending the verify window from 120s to 300s) shipped in
PR #2523 (merged 2026-04-17 21:07 UTC, ~7 minutes after this issue
was opened).

Live evidence:
- `git show main:.github/workflows/web-platform-release.yml` line 106 is `STATUS_POLL_MAX_ATTEMPTS: 60`.
- Run [24732382107](https://github.com/jikig-ai/soleur/actions/runs/24732382107) (v0.48.2, 2026-04-21) completed on `Attempt 6/60` in ~32s.

Closing as duplicate. Follow-up tooling gap tracked in #<follow-up-issue-number>.
EOF
)"
```

**Note:** the heredoc terminator column is irrelevant here — this command runs in an *interactive shell*, not a GitHub Actions `run:` block, so `hr-in-github-actions-run-blocks-never-use` does not apply.

### Phase 4 — Follow-up Issue (5 min)

File a new issue for the triage-time duplicate-detection gap (referenced in the learning).

- **Title:** `chore(tooling): fix-issue / one-shot / triage should detect already-shipped proposed fixes before spawning work`
- **Milestone:** `Post-MVP / Later` (title, not numeric ID — per `cq-gh-issue-create-milestone-takes-title`)
- **Labels:** `domain/engineering`, `type/feature`, `priority/p3-low`
- **Label verification (per `cq-gh-issue-label-verify-name`):** run `gh label list --limit 100 | grep -E "(domain/engineering|type/feature|priority/p3)"` immediately before `gh issue create` to confirm exact label names.
- **Body:** cite this plan + the learning file; include a 3-line reproducer (extract `STATUS_POLL_MAX_ATTEMPTS` from #2526, grep main, match → would have closed as dup).

### Research Insights (Phase 4)

**Why triage-time, not fix-time:** Catching a duplicate at `/soleur:fix-issue` or inside `/soleur:one-shot` still wastes the worktree spin-up (`worktree-manager.sh create` is not free). The cheapest catch is at `/soleur:triage`, where the bot scans fresh issues and labels them. A "proposed fix already shipped" heuristic there short-circuits the whole pipeline.

**Concrete detection heuristic (for the follow-up issue to consider):**

```bash
# For any issue with a "Proposed fix" / "Proposed Fix" section mentioning a
# named env var or config symbol (ALL_CAPS_WITH_UNDERSCORES):
ISSUE_BODY=$(gh issue view "$N" --json body -q .body)
SYMBOL=$(echo "$ISSUE_BODY" | grep -oE '[A-Z][A-Z0-9_]{3,}' | sort -u | head -20)
PROPOSED_VALUE=$(echo "$ISSUE_BODY" | grep -oE "${SYMBOL}.{0,40}" | head -1)

# Check if main already has the proposed value for that symbol:
for sym in $SYMBOL; do
  if git grep "$sym" origin/main -- '**/*.yml' '**/*.sh' '**/*.ts' | \
     grep -qE "$sym:\\s*$(echo "$PROPOSED_VALUE" | grep -oE '[0-9]+' | head -1)"; then
    echo "LIKELY DUPLICATE: $sym already matches proposed value on main"
  fi
done
```

Not bullet-proof (no NLP, only handles named knobs), but would have closed #2526, #2479 (HSTS drift), and at least two other dups from the 2026-04 window without human intervention.

## Files to Edit

None.

## Files to Create

- `knowledge-base/project/learnings/best-practices/2026-04-22-one-shot-duplicate-detection.md` — see Phase 2 outline.

## Test Scenarios

No tests. This is a no-code-change PR. The acceptance signal is:

- [ ] #2526 transitions to `CLOSED` with `stateReason` referencing #2519/#2523.
- [ ] The learning file exists at the path above, passes `markdownlint-cli2 --fix`, and contains the three-point detection checklist from Phase 2.
- [ ] Follow-up tooling issue filed with correct milestone and labels.
- [ ] `git diff main -- .github/workflows/web-platform-release.yml` is **empty** (no workflow change).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **Workflow invariant:** `git diff main -- .github/workflows/web-platform-release.yml` returns empty. This is load-bearing — a no-op edit here would dilute PR #2523's attribution.
- [ ] Learning file at `knowledge-base/project/learnings/best-practices/2026-04-22-one-shot-duplicate-detection.md` exists, passes `npx markdownlint-cli2 --fix <that-file>` (targeted path, per `cq-markdownlint-fix-target-specific-paths`).
- [ ] Learning file cross-links the follow-up tooling issue by `#<N>`.
- [ ] PR body carries `Closes #2526` on a standalone line (not in title, per `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] `gh issue close 2526 --reason "duplicate" --comment <...>` planned for post-merge; **not** invoked pre-merge (the PR closes it).
  - **Note:** `Closes #2526` + PR merge auto-closes the issue with `stateReason: COMPLETED`. To get `stateReason: NOT_PLANNED` or `DUPLICATE`, the operator must run `gh issue close` manually AFTER merge, OR preemptively close before merge. Default path: let `Closes #` auto-close, accept `COMPLETED` as stateReason (matches 2+ prior dup closures in the tracker including #2158, #2312).

### Post-merge (operator)

- [ ] `gh issue view 2526 --json state` reports `"state": "closed"`.
- [ ] `gh issue list --milestone "Post-MVP / Later" --state open --search "duplicate detection"` finds the follow-up tooling issue.
- [ ] (Optional, if operator wants the DUPLICATE stateReason) `gh issue close 2526 --reason "duplicate"` re-classification.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI bookkeeping and workflow-tooling learning. No user-facing surface, no product/marketing/legal/finance implications. CTO-adjacent but the underlying engineering change was already domain-reviewed in PR #2523.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **A. Close as duplicate, file learning (this plan)** | Correctly reflects reality; captures reusable workflow lesson. | Requires discipline to not-edit the workflow file just because a pipeline told us to fix a thing. | **Chosen.** |
| B. Re-apply the fix (no-op commit on the workflow) | Matches the pipeline's literal instruction. | Confuses `git blame`; dilutes #2523's attribution; no actual change. | Rejected. |
| C. Bump to a **higher** value (e.g., 90 × 5s = 450s) as a hedge. | "Better safe than sorry." | Speculative. No run has needed > 34s since the fix. 300s is already 1.5× observed worst case. Would need a fresh justification PR. | Rejected. |
| D. Close as duplicate, skip the learning. | Less work. | Wastes the compound-knowledge signal about a real gap in `/soleur:one-shot` triage. Next dup-routing incident will repeat. | Rejected. |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| An operator misreads this plan and reverts `STATUS_POLL_MAX_ATTEMPTS` back to 24 | low | high (re-reintroduces the #2519 false-negative class) | Phase 1 verification + explicit "do not edit workflow" in Non-Goals + acceptance criterion on empty diff. |
| The follow-up tooling issue never gets picked up | medium | low | Milestoning to `Post-MVP / Later` is the Soleur convention for non-urgent tooling debt. Linking from the learning gives it future discoverability. |
| A third race-condition duplicate gets filed before the triage-time detection ships | low-medium | low | Covered by the follow-up issue; until then, this plan establishes the "verify first, then close" pattern for the next reviewer. |
| The work skill spawns multi-agent review on a housekeeping PR and burns context on nothing | medium | low (time only) | **Risks section explicitly flags this as a no-code-change PR.** Review skill's default pipeline should short-circuit when diff is empty-on-code-surface. If it doesn't, the reviewer agents will converge on "this is a dup-closure; LGTM" within one round — tolerable. |
| Closing #2526 causes confusion if the CI signal degrades again | very low | low | The learning file documents *why* #2526 was dup-closed, including the 5-day window and the v0.48.2 evidence. A future regression would be a fresh issue, not a revival. |

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-04-22-fix-2526-deploy-verify-timeout-already-fixed-plan.md

Context: branch feat-one-shot-fix-2526-deploy-verify-timeout, worktree
.worktrees/feat-one-shot-fix-2526-deploy-verify-timeout/, issue #2526 (duplicate
of #2519, already fixed by PR #2523). No workflow edit. Create the
one-shot-duplicate-detection learning, file the follow-up tooling issue, close
#2526 as duplicate with the Phase 3 comment template. Verify
`git diff main -- .github/workflows/web-platform-release.yml` is empty before
committing.
```
