---
title: "Bun version probe for FPE-class re-evaluation (#3692)"
date: 2026-05-12
issue: 3692
pr: 3709
branch: feat-ci-followups-scoping
worktree: .worktrees/feat-ci-followups-scoping
spec: knowledge-base/project/specs/feat-ci-followups-scoping/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-12-ci-3672-followups-scoping-brainstorm.md
parent_plan: knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md
lane: single-domain
brand_survival_threshold: none
status: Draft
---

# Plan: Bun version probe for FPE-class re-evaluation

**Issue:** #3692
**Branch:** `feat-ci-followups-scoping`
**Draft PR:** #3709
**Brainstorm:** [`knowledge-base/project/brainstorms/2026-05-12-ci-3672-followups-scoping-brainstorm.md`](../brainstorms/2026-05-12-ci-3672-followups-scoping-brainstorm.md)
**Spec:** [`knowledge-base/project/specs/feat-ci-followups-scoping/spec.md`](../specs/feat-ci-followups-scoping/spec.md)

## Overview

Bump `.bun-version` from `1.3.11` to `1.3.14` (latest published 1.3.x at plan time) on PR #3709 and observe the existing `test-bun` CI shard. Outcome captured in `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` regardless of green/red. On FPE-class regression, the same commit is amended to revert to 1.3.11 and the learning records the failing patch. The PR merges either way — the deliverable is the recorded probe outcome, which informs whether future re-evaluation of in-process Bun parallelism (`bun test --max-pool-size`) is unlocked.

This is a probe, not a unilateral version bump commitment. The sequential test runner in `scripts/test-all.sh` is **not** touched — it remains as defense-in-depth even on a green probe.

#3693 and #3694 are NOT in scope (see brainstorm doc for the scope pivot rationale). They have no causal link to the probe outcome and are tracked separately under their own re-evaluation triggers.

## Research Reconciliation — Spec vs. Codebase

| # | Claim | Codebase reality (verified at plan time) | Plan response |
|---|---|---|---|
| 1 | "Bump to latest 1.3.x patch" (target unspecified) | `npm view bun@latest version` → `1.3.14` (verified 2026-05-13). | Target pinned to **1.3.14** by literal version string (not `@latest`). Re-verify in Phase 1; if newer 1.3.x published, update target and amend this plan body before Phase 2. |
| 2 | "Run `bun test test/` and `bun test plugins/soleur/`" (issue body) | `scripts/test-all.sh` lines 79-83 run the 3 named bun tests; lines 91-93 run `bun test plugins/soleur/` + `bash scripts/validate-blog-links.sh`. All gated on `want_bun()`. Total: 5 invocations in the `test-bun` CI shard. | Probe surface is exactly the `test-bun` shard. The `validate-blog-links.sh` invocation is in the shard but is not a bun-runtime test — see FPE-detection rule in Phase 3. |
| 3 | "Webplat is Vitest, not Bun" | Confirmed: `apps/web-platform/package.json` → `"test:ci": "vitest run"`. | Probe scope excludes webplat. |
| 4 | Workflow count: "all CI workflows read `.bun-version`" | **Actually 5 of 7 read it.** `bun-version-file: ".bun-version"`: `ci.yml` (3 occurrences across `test-webplat`, `test-bun`, `web-platform-build` jobs), `main-health-monitor.yml:35`, `scheduled-bug-fixer.yml:70`, `scheduled-ship-merge.yml:61`, `scheduled-ux-audit.yml:137`. **NOT tracked:** `skill-security-scan-corpus.yml:38` and `skill-security-scan-pr-trailer.yml:51` both pin `bun-version: latest`. | No edits to the 5 tracked workflows. The 2 floating workflows are an out-of-scope parallel exposure surface — see Risks #1. |

## Files to Edit

- `.bun-version` — `1.3.11` → `1.3.14`.
- `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` — append one `## 2026-05-12 probe: 1.3.14 <outcome>` section.

## Files to Create

None.

## Implementation Phases

### Phase 1 — Pre-bump verification

1. Read `.bun-version`; confirm `1.3.11`.
2. Re-confirm latest 1.3.x: `npm view bun versions --json | jq -r '.[]' | grep -E '^1\.3\.[0-9]+$' | tail -1`. If newer than `1.3.14`, edit this plan body's target version + Research Reconciliation row 1 in a separate docs commit before Phase 2.
3. Confirm no other changes are pending: `git status --short` should show only docs files (brainstorm/spec/plan/tasks).

### Phase 2 — Bump and push

1. `echo "1.3.14" > .bun-version` (preserves trailing newline matching existing file shape).
2. Commit:
   ```
   chore(ci): probe bun 1.3.14 for FPE-class re-evaluation

   Closes #3692. Sequential test runner left in place as defense-in-depth.
   Outcome captured in 2026-03-20 FPE learning file.
   ```
3. `git push`. CI fires.

### Phase 3 — Observe and classify

Watch the PR's check run (`gh run watch <run-id> --exit-status` for wall-clock bound, or the PR Checks tab). **First-attempt authoritative** — if GitHub auto-retries a job, the first attempt's outcome is the probe data; re-runs are diagnostic only.

**Classification (mutually-exclusive, in priority order):**

1. **FPE-class detected in `test-bun` shard** → Phase 4b (revert).

   Detection: run `gh run view <run-id> --log --job <test-bun-job-id> | grep -nE 'SIGFPE|panic:|Floating point (error|exception)|oh no:'` against the failing job log. Any match in any of the 5 `test-bun` shard invocations is a positive. This rule has precedence over any co-occurring assertion failure in the same shard — co-existing FPE + Vitest assertion is still classified FPE.

   Note: `validate-blog-links.sh` (invocation 5 in `test-bun`) is bash, not bun-runtime. A failure there is never FPE-class; route to case 3.

2. **All 5 `test-bun` shard invocations green AND all other shards green** → Phase 4a (keep).

3. **Inconclusive** — `test-bun` test-level failure (Vitest assertion, no FPE grep match) OR any non-`test-bun` shard failure (`test-webplat`, `test-scripts`, `web-platform-build`, `e2e`).

   Disposition: STOP work on `.bun-version`. Leave the file at `1.3.14` and the PR in draft. Open a comment on PR #3709 with the failing shard + the operator's read. Append a `## 2026-05-12 probe: 1.3.14 inconclusive` section to the learning file describing the failure mode. Do NOT auto-revert and do NOT mark ready — the probe is paused until the unrelated red is understood. Probe re-runs once the unrelated red is fixed (force-push amend OK, same fallback as 4b).

### Phase 4a — Green outcome

Amend the Phase 2 commit to fold the learnings append into the same commit (preserves single-commit PR shape):

```bash
cat >> knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md <<'EOF'

## 2026-05-12 probe: 1.3.14 clean

Bumped `.bun-version` 1.3.11 → 1.3.14 in PR #3709. All 5 `test-bun` shard invocations green on Ubuntu 22.04 GitHub-hosted runner. Sequential runner kept as defense-in-depth — one green probe is not proof of class elimination for combined-suite execution. Next probe target: next minor bump.
EOF
git commit --amend --no-edit
git push --force-with-lease
```

Then mark PR #3709 ready.

### Phase 4b — FPE outcome

Amend the Phase 2 commit to (a) revert `.bun-version` and (b) append the failure record, single-commit shape:

```bash
echo "1.3.11" > .bun-version
cat >> knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md <<'EOF'

## 2026-05-12 probe: 1.3.14 FPE class still live

Bumped `.bun-version` 1.3.11 → 1.3.14 in PR #3709. FPE-class fired on <surface(s)>:

<copied grep match + full job URL + runner OS>

Reverted to 1.3.11 in-place via `git commit --amend`. Sequential test runner remains load-bearing. Next probe target: next minor bump.
EOF
git commit --amend --no-edit
git push --force-with-lease
```

If `--force-with-lease` rejects (someone else pushed to the branch since last fetch — e.g. claude[bot] review-fix amend), **fallback procedure:**

```bash
git fetch origin
git reset --soft origin/feat-ci-followups-scoping   # only if local is behind
# Re-apply the revert + learnings as a new commit (two-commit PR shape, acceptable)
echo "1.3.11" > .bun-version
# learnings append already in working tree from above
git add .bun-version knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md
git commit -m "revert: bun 1.3.14 → 1.3.11 (FPE class still live)"
git push
```

Then file the next probe issue: `gh issue create --title "ci: bun version probe for FPE-class re-evaluation (post-1.3.14)" --label "domain/engineering,type/chore,priority/p3-low" --milestone "Post-MVP / Later" --body "Re-evaluate FPE class on the next minor Bun bump. Last probe: PR #3709 (FPE fired on 1.3.14)."`

Mark PR #3709 ready.

### Phase 5 — Close (post-merge)

`gh issue close 3692 --comment "Probed in PR #3709. Outcome: <green | FPE | inconclusive>. Learning: knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md."`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `.bun-version` reflects probe outcome (`1.3.14` on green; `1.3.11` on FPE).
- [ ] Learning file appended with a single dated section (`clean`, `FPE class still live`, or `inconclusive`).
- [ ] PR body contains `Closes #3692`.
- [ ] CI green on the PR's head SHA.
- [ ] Single feature commit on `feat-ci-followups-scoping` (probe + learnings folded via amend). Brainstorm/spec/plan/tasks docs commits are separate.

### Post-merge (operator)

- [ ] On FPE: follow-up probe issue created (see Phase 4b).
- [ ] `gh issue close 3692` with outcome summary.

## Test Strategy

The probe IS the test — signal lives in CI on PR #3709's `test-bun` shard (Ubuntu 22.04 GitHub-hosted runner exercising 5 bun-runtime invocations). Local re-run is not part of the protocol (local Bun version may differ from CI's installed version; FPE class is sensitive to runner OS + installed binary). On FPE, capture the full failing-job log via `gh run view <run-id> --log` into the learning section before the amend — GitHub GC's run logs after 90 days.

## User-Brand Impact

**If this lands broken, the user experiences:** Nothing user-facing. `.bun-version` controls CI's installed Bun binary; production runtime is Node 22 via `apps/web-platform`'s `actions/setup-node`. A bad Bun version produces red CI, not user-visible regressions.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — no user data, credentials, or production code paths touched.

**Brand-survival threshold:** `none` — internal CI tooling change. The diff touches no path matching the preflight Check 6 sensitive-path canonical regex (no schema, migration, auth, API route, or `.sql` files), so the `none` declaration carries no scope-out requirement.

## Domain Review

**Domains relevant:** Engineering (single-domain lane, carried forward from brainstorm).

### Engineering

**Status:** reviewed (brainstorm carry-forward + 4-agent plan-review panel applied)
**Assessment:** Probe shape is minimal and reversible. Bumping a CI-only version pin with a documented revert protocol carries near-zero blast radius. Keeping `scripts/test-all.sh`'s sequential isolation regardless of probe outcome is correct — one green probe is necessary but not sufficient for class elimination on combined-suite execution. Plan-review pass corrected workflow enumeration (5 not 7), tightened FPE-detection to an explicit grep pattern, added force-push fallback, and added mixed-mode precedence rule.

## Risks

1. **Parallel uncontrolled exposure surface.** `skill-security-scan-corpus.yml:38` and `skill-security-scan-pr-trailer.yml:51` already pin `bun-version: latest` — they have been running on Bun 1.3.14 (or whatever `setup-bun` resolves as `latest`) on every workflow fire, independent of this probe. If FPE class still fires on 1.3.14, those workflows are already silently exposed. Out of scope here — file a follow-up to align them with the `.bun-version` pin only if this probe surfaces an FPE outcome (then the floating pin becomes a CVE-shaped risk). On green, no follow-up needed.

2. **Force-push race.** Phase 4 amends + `--force-with-lease`. Mitigated by the lease flag and by the fact that PR #3709 is single-author. Concrete fallback documented in Phase 4b for the lease-rejected case.

3. **Probe inconclusive on unrelated flake.** Phase 3 case 3 halts on `inconclusive` rather than guessing. Operator decides: retry after unrelated red is fixed, or close PR + re-probe later.

## Sharp Edges

- **Pin the explicit version string.** `.bun-version` MUST contain `1.3.14`, not `latest` or `1.3.x`. The `setup-bun` action with `bun-version-file:` interprets the file contents literally.
- **First-attempt authoritative.** If GitHub auto-retries a failed job, the FIRST attempt's outcome is the probe data. Re-runs are diagnostic-only and noted in the learnings section if they disagree.
- **FPE-class grep is positive-precedence.** A `test-bun` shard with both an FPE crash and a co-occurring Vitest assertion failure is classified FPE (Phase 4b). Do not let an assertion failure mask a crash signal.
- **Force-push only safe on single-author PR.** Phase 4b amend assumes no co-author/bot has pushed since the Phase 2 SHA. If bot review-comment annotations exist on the original SHA, they become outdated (visible but pinned to old SHA) — acceptable for a draft probe PR but document in the learning section if relevant.
- **Skill-security-scan workflows float independently.** Plan does NOT pin those to `.bun-version`. If a future operator wants a clean unified pin, that's a separate PR and a separate scoping discussion.

## Open Code-Review Overlap

Verified via `gh issue list --label code-review --state open` against `.bun-version`, `scripts/test-all.sh`, `apps/web-platform/test/`, and `.github/workflows/ci.yml`:

- `.bun-version`, `scripts/test-all.sh`, `.github/workflows/ci.yml` — None.
- `apps/web-platform/test/` — #3331 (extract shared SDK fixture harness) touches files in this directory but is a separate concern. **Disposition: Acknowledge — scope-out remains open, untouched by this probe.**
