---
title: "fix: regen shard manifest — backfill run-health-emit.test.sh committed weight row"
type: fix
date: 2026-11-11
slug: fix-run-health-emit-weight-row
branch: feat-one-shot-run-health-emit-weight-row
issue: none
closes: none
lane: cross-domain
domain: engineering
priority: p1-high
brand_survival_threshold: none
---

# fix: regen shard manifest — backfill run-health-emit.test.sh committed weight row

> Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch (one-shot pipeline path, no brainstorm ran).

## Enhancement Summary

**Deepened on:** 2026-11-11
**Sections enhanced:** 0 content sections needed correction — every premise, citation, and literal was re-verified live and held. The deepen pass added this gate-evidence record.
**Research agents used:** none spawnable — this ran inside a Task subagent of the one-shot pipeline with no subagent-spawn tool; sequential-fallback inline verification substituted (disclosed as `Reviewed-Coverage: sequential-fallback` in `## Context`).

### Deepen-pass gate results (soleur:deepen-plan Phases 4.6–4.13)

| Gate | Result |
|---|---|
| 4.6 User-Brand Impact | PASS — `none` threshold valid; Files-to-Edit (`scripts/*.tsv`) match zero `SENSITIVE_PATH_RE` alternatives, so no scope-out bullet required |
| 4.7 Observability | PASS — all 5 fields present, non-placeholder; `bash` on preflight Check 10's probe-verb allowlist; no `ssh`; measured 1.24s ≪ 15s sandbox cap; `ALL PASS` is a matchable literal. The suite-shaped-command detection proxy (`[-.]test\.`) matches the probe path — argued down in `## Observability` Probe notes: the probe *is* the signal `liveness_signal.what` names (the gate's own verdict line); no smaller command prints it |
| 4.8 PAT sweep | PASS — zero matches |
| 4.9 UI wireframe | SKIP — no UI-surface files |
| 4.10 Encryption posture | SKIP — no persistent store or new cross-component connection |
| 4.11 Guard Contract | SKIP — deliverable is generated data satisfying an existing guard, not a new guard |
| 4.12 Scope Check | PASS — exactly 1 unfenced section; Ask Mapping rows all `mapped`; provenance rows `asked` or `inferred` with justification; `Recommendation:` present; no `status: BLOCKED` |
| 4.13 Task Design | SKIP — no autonomous task introduced |
| Network-outage / Downtime-cutover | SKIP — no triggers (no SSH/hot-path/infra-reboot/DDL/deploy work) |

### Live re-verification performed this pass (2026-11-11)

- `gh pr view 12565 --json state,mergedAt` → `MERGED`, `2026-11-11T17:33:39Z` — premise held.
- `gh pr view 12650 --json state` → `OPEN` — sibling still carries the identical delta; the `### Merge ordering` section stands and its re-sync rule (`gh pr view 12650` at every re-sync) remains load-bearing.
- `git rev-parse aae21955e6` resolves; `git merge-base --is-ancestor` confirms it on both `HEAD` and `origin/main` — base-commit attribution held.
- All cited paths exist (ADR-240, both learnings, the #12565 sibling plan, `tasks.md`).
- Zero AGENTS rule-ID citations in the plan body — no fabricated/retired-ID exposure.
- String-literal consistency (`ALL PASS`, `1272`, `floor`, `0 moved, 1 new, 0 no longer registered`, `registration(s) with no committed weight row`) checked across Helper sections, ACs, Test Scenarios, and `tasks.md` — one canonical value each.
- AC greps scope `scripts/*.tsv` only; neither the plan nor `tasks.md` can self-match — no `--exclude` flags needed.
- `tasks.md` consistent with the plan (generator command, row greps, `ALL PASS`, exemptions untouched) — no correction propagation required.

### New considerations discovered

- None. The deepen pass found no corrective delta; the plan's minimal-by-construction shape (one generator run + one verification) survived every applicable gate.

## Overview

Main CI is red on post-merge commit `aae21955e6` (PR #12565, "WIP: feat-12532-degraded-run-forensics", merged 2026-11-11T17:33:39Z): the `test-scripts (3/8)` job fails suite `scripts/test-all-corpus-weight-budget` because `plugins/soleur/scripts/run-health-emit.test.sh` — a registered test suite added by #12565 — carries no committed weight row. The gate's contract is `unmeasured != exempt` (its M4 fixture arm): every registered label must have a row in `scripts/suite-durations.tsv` or a bounded exemption in `scripts/suite-weight-exemptions.tsv`.

The fix is deliberately **not** a hand-edit: the two tables are checked-in *generated* data (ADR-240 — "generated offline and committed … regenerated on conflict, never hand-merged"). The canonical generator `python3 scripts/regenerate-shard-manifest.py --incremental --write` (the `# regen:` header inside `scripts/suite-shard-legs.tsv` itself) writes the new registration's floor rows, assigns a shard leg via sticky-LPT, and stamps the `generated-at` headers.

## Research Insights

### Premise Validation

Every premise in the brief was re-verified against the live repo (2026-11-11):

| Cited premise | Verification | Result |
|---|---|---|
| `plugins/soleur/scripts/run-health-emit.test.sh` exists, added by #12565 | file present (100755); `gh pr view 12565` → `MERGED` 2026-11-11T17:33:39Z | held |
| Suite lacks a committed weight row | `grep run-health-emit scripts/suite-{durations,shard-legs}.tsv` → rc 1 (absent from both) | held |
| `test-all-corpus-weight-budget` fails on it | ran it: `[check] registration(s) with no committed weight row: plugins/soleur/scripts/run-health-emit.test.sh` → 13 passed, 1 failed | held |
| `# regen:` header names the generator | `scripts/suite-shard-legs.tsv:8` → `python3 scripts/regenerate-shard-manifest.py --incremental --write` | held |
| Expected delta matches a sibling regen | `gh pr diff 12650` shows the identical rows: `run-health-emit.test.sh\t1272\tfloor` (durations, alphabetically before `run-in-pid-namespace`) and `run-health-emit.test.sh\t2` (shard-legs), plus `generated-at` bumps | held |
| Generator produces that delta | dry-run `python3 scripts/regenerate-shard-manifest.py --incremental` → `1 new at floor 1272ms … 0 moved, 1 new, 0 no longer registered`; worktree left clean | held |
| Proposed mechanism vs ADR corpus | ADR-240 (`shard-assignment-is-checked-in-derived-data`) **Decision §1**: `regenerate-shard-manifest.py` is the canonical writer; §3: untabled labels hash-fall-back (why CI ran the suite fine while the budget gate reds) | mechanism is the ADR-prescribed one, not a rejected alternative |

Nothing stale. The `gh pr view` field `merged` is not a valid JSON field (used `mergedAt`/`state` instead).

### Property List (Phase 0.6b)

The ask, restated as observable properties:

1. Every registered `*.test.sh` label carries a committed row in `scripts/suite-durations.tsv`.
2. `plugins/soleur/scripts/run-health-emit.test.sh` carries a shard-leg assignment in `scripts/suite-shard-legs.tsv`.
3. `bash scripts/test-all-corpus-weight-budget.test.sh` exits 0 (main CI green).

### Cut List

None. The ask proposes zero new machinery — it prescribes running the mechanism that already exists (`regenerate-shard-manifest.py`, ADR-240). No alternative mechanism was considered because the ADR forbids the alternative (hand-editing generated tables) and the generator's dry run already produces exactly the required rows.

### Relevant file paths

- `scripts/regenerate-shard-manifest.py` — canonical generator (`--incremental --write` = suite added/removed path; header lines 31–85 document the modes).
- `scripts/suite-durations.tsv` — committed per-suite weights; insertion point after `plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh` (~line 110), before `plugins/soleur/scripts/run-in-pid-namespace.test.sh` (~line 111).
- `scripts/suite-shard-legs.tsv` — committed leg assignments; same alphabetical insertion point (~line 113).
- `scripts/test-all-corpus-weight-budget.test.sh` — the red gate; M4 arm pins `unmeasured != exempt`; success literal `test-all-corpus-weight-budget: ALL PASS (<N> assertions, 0 failed)`.
- `plugins/soleur/scripts/run-health-emit.test.sh` — the unmeasured registration (do not touch).
- `scripts/suite-weight-exemptions.tsv` — the bounded-exemption ledger (not needed: floor 1272ms ≪ 600s cap).

### Institutional learnings applied

- `2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md` — a PR carrying a regenerated file that siblings also regenerate cannot stay mergeable; on conflict, **re-run the generator, never hand-merge** (ADR-240). Open PR #12650 already carries this exact delta — merge-ordering handling is a dedicated section below.
- `2026-11-07-a-required-shard-on-its-timeout-edge-made-the-merge-queue-a-coin-flip.md` — leg balance is load-bearing; letting the generator pick the leg (sticky-LPT) rather than hand-picking one is the correctness path.
- `knowledge-base/project/learnings/best-practices/` — n/a for shape.

### Related issues / PRs

- PR #12565 — MERGED; introduced `run-health-emit.test.sh` without the regen (root cause). Plan of record: `knowledge-base/project/plans/2026-11-10-feat-run-health-instrumentation-plan.md`.
- PR #12650 — OPEN ("WIP: feat-one-shot-12587-probe-field-fix"); its regen already produced the identical `run-health-emit` rows plus its own new suite's rows. **Collision noted; see Merge Ordering.**

### Conventions

- Generated tables: edit only via the generator; conflict resolution = re-run it (ADR-240 §"generated, committed, never hand-merged").
- Floor weight for an unmeasured suite: `default-weight-ms=1272` (header of both tables).
- Commit subject convention for the repo: `fix:` prefix.

## Proposed Solution

One generator run, two generated files, one verification. No code changes.

### Implementation Phases

**Phase 1 — Regenerate (the whole fix).**
From the worktree root:

```bash
python3 scripts/regenerate-shard-manifest.py --incremental --write
```

<!-- verified: 2026-11-11 source: `# regen:` header in scripts/suite-shard-legs.tsv + dry-run executed locally (1 new floor row, 0 moved, 0 dropped) -->

Expected diff (verified twice — the local dry-run output above and the byte-identical delta in open PR #12650):

- `scripts/suite-durations.tsv`: `plugins/soleur/scripts/run-health-emit.test.sh<TAB>1272<TAB>floor` inserted alphabetically between `resolve-regenerable-conflicts.test.sh` and `run-in-pid-namespace.test.sh`; `# generated-at=` header re-stamped.
- `scripts/suite-shard-legs.tsv`: `plugins/soleur/scripts/run-health-emit.test.sh<TAB><leg>` (leg `2` in #12650's regen against the same incumbent table — the generator's sticky-LPT picks the least-loaded leg; assert *a* leg in `1..8`, not the literal, in case main moved); `# generated-at=` re-stamped.
- **Nothing else.** The dry-run promised `0 moved, 0 no longer registered`; any other row delta means the incumbent moved under us — re-sync main and re-run the generator rather than reconciling by hand.

**Phase 2 — Verify locally.**

```bash
bash scripts/test-all-corpus-weight-budget.test.sh   # exit 0, prints "ALL PASS"
git diff --stat                                        # exactly 2 files, +4/−2 (2 rows + 2 header re-stamps)
grep -P 'run-health-emit\.test\.sh\t1272\tfloor' scripts/suite-durations.tsv
grep -P 'run-health-emit\.test\.sh\t[1-8]$' scripts/suite-shard-legs.tsv
```

<!-- verified: 2026-11-11 source: bash run executed locally (currently reds with "registration(s) with no committed weight row"), prints ALL PASS literal on green per the script's final echo -->

**Phase 3 — Commit + PR.**

`git add scripts/suite-durations.tsv scripts/suite-shard-legs.tsv`, commit `fix: backfill run-health-emit.test.sh weight row (shard-manifest regen)`, PR body notes the #12565 follow-up and the #12650 merge-ordering note below. `semver:patch` label class (bug fix). CI green = the `test-scripts (3/8)` leg that was red.

### Merge ordering vs PR #12650 (generated-artifact conflict, learning 2026-09-19)

#12650 carries the identical `run-health-emit` rows (observed 2026-11-11 via `gh pr diff 12650` — a time-stamped observation; re-read its state with `gh pr view 12650` at every re-sync, since a sibling state can move mid-flight). Whichever lands first wins:

- **This PR lands first:** #12650 rebases and re-runs its own generator (it already produces the row; the conflict reduces to the `generated-at` stamp).
- **#12650 lands first:** sync main, re-run the generator — it reports `0 new`; this PR then contains no TSV delta and is closed as superseded after verifying `main`'s `test-scripts` job is green.
- **Never** resolve a TSV conflict by hand-editing; the resolver is the generator.

## Files to Edit

- `scripts/suite-durations.tsv` — generator-written only (+1 `floor` row, `generated-at` header).
- `scripts/suite-shard-legs.tsv` — generator-written only (+1 leg row, `generated-at` header).

## Files to Create

None. (Planning artifacts — this plan, `tasks.md` — are committed separately and are not product files.)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 issues) searched for bodies containing `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv`, `scripts/regenerate-shard-manifest.py`, `plugins/soleur/scripts/run-health-emit.test.sh` — zero matches. (Check run 2026-11-11.)

## User-Brand Impact

- **If this lands broken, the user experiences:** no user-facing artifact — the worst case is a wrong shard-leg assignment making a `test-scripts` CI leg slower (imbalance), or the weight row under-counting a suite's true cost; the blast radius is the repo's own CI scheduling, not a user surface.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the diff is generated scheduling metadata (durations in ms, leg integers); no user data, credentials, or paths outside the repo.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `single-user incident` — the change is derived CI-scheduling data for the repo's own test runner; no end-user surface, no stored data, no auth/money path. Sensitive-path check: diff paths (`scripts/*.tsv`) match zero alternatives of preflight Check 6's `SENSITIVE_PATH_RE`, so no scope-out bullet is required.

## Observability

```yaml
liveness_signal:
  what: "committed-weight budget gate verdict — test-all-corpus-weight-budget.test.sh final line"
  cadence: "every test-scripts CI leg (n/8 shards) and every local scripts/test-all.sh run"
  alert_target: "GitHub Actions check status on the PR / main pipeline"
  configured_in: "scripts/test-all-corpus-weight-budget.test.sh (cap literal + unmeasured-registration predicate); rows committed in scripts/suite-durations.tsv"

error_reporting:
  destination: "GitHub Actions job log for the test-scripts leg"
  fail_loud: "stderr: '[check] registration(s) with no committed weight row: <label>' + '[FAIL] canonical corpus violates the committed-weight budget', exit 1"

failure_modes:
  - mode: "a registered *.test.sh suite merges without a durations-table row (this incident's class)"
    detection: "the gate prints 'registration(s) with no committed weight row: <label>' and exits 1 — live instance observed 2026-11-11 on plugins/soleur/scripts/run-health-emit.test.sh"
    alert_route: "test-scripts CI leg reds → blocks the PR and main pipeline"
  - mode: "generator run produces churn beyond the +1 row (incumbent moved / stale checkout)"
    detection: "git diff shows moved or dropped rows, or the generator's summary line reports != '0 moved, 1 new, 0 no longer registered'"
    alert_route: "local verification step fails; re-sync main and re-run the generator instead of hand-editing"
  - mode: "sibling regen lands first and this PR's delta becomes a conflict or a no-op"
    detection: "post-sync dry-run reports 0 new; or git merge-conflict on generated-at / adjacent rows"
    alert_route: "re-run generator (never hand-merge); close as superseded if delta is empty and main is green"

logs:
  where: "GitHub Actions job log for the failing leg; local stdout of the verify command"
  retention: "GitHub Actions default (90 days); local output ephemeral"

discoverability_test:
  command: bash scripts/test-all-corpus-weight-budget.test.sh
  expected_output: ALL PASS
```

Probe notes: `bash` is on preflight Check 10's `PROBE_VERB_ALLOWLIST`; measured runtime 1.24s (well under the 15s sandbox cap); `ALL PASS` is the literal substring of the script's success line `test-all-corpus-weight-budget: ALL PASS (<N> assertions, 0 failed)`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "run the canonical generator `python3 scripts/regenerate-shard-manifest.py --incremental --write` (per the `# regen:` header in scripts/suite-shard-legs.tsv) so the generator writes the new registration's floor rows itself" | Phase 1 | mapped |
| 2 | "`plugins/soleur/scripts/run-health-emit.test.sh\t1272\tfloor` appended alphabetically in `scripts/suite-durations.tsv`, and `plugins/soleur/scripts/run-health-emit.test.sh\t2` in `scripts/suite-shard-legs.tsv`, plus `generated-at` header updates" | Phase 1 expected-diff block + AC1–AC3 | mapped |
| 3 | "Verify: `bash scripts/test-all-corpus-weight-budget.test.sh` exits 0" | Phase 2 + AC4 | mapped |
| 4 | "the discoverability test is `bash scripts/test-all-corpus-weight-budget.test.sh` exiting 0, plus green test-scripts shards on the PR's own CI run" | `## Observability` block + AC5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/suite-durations.tsv` edit | "`plugins/soleur/scripts/run-health-emit.test.sh\t1272\tfloor` appended alphabetically in `scripts/suite-durations.tsv`" | asked |
| `scripts/suite-shard-legs.tsv` edit | "`plugins/soleur/scripts/run-health-emit.test.sh\t2` in `scripts/suite-shard-legs.tsv`" | asked |
| Generator invocation (Phase 1) | "run the canonical generator `python3 scripts/regenerate-shard-manifest.py --incremental --write`" | asked |
| Weight-budget verify (Phase 2) | "Verify: `bash scripts/test-all-corpus-weight-budget.test.sh` exits 0" | asked |
| Commit + PR (Phase 3) | — | inferred — justification: the fix must land on `main` through the branch's PR for main CI to go green; the pipeline's own vehicle |
| Merge-ordering note vs #12650 | "verified identical to what a sibling regen in open PR #12650 produced" | asked (the brief names the sibling; the handling rule derives from ADR-240 + learning 2026-09-19) |

### Split Assessment

- Subsystems touched: 1 — `scripts`
- Planned files: 2 | Estimated changed lines: ~4 (2 rows + 2 `generated-at` headers)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `scripts/suite-durations.tsv` contains a row `plugins/soleur/scripts/run-health-emit.test.sh<TAB>1272<TAB>floor` in alphabetical position (between `resolve-regenerable-conflicts.test.sh` and `run-in-pid-namespace.test.sh`).
- [ ] AC2 — `scripts/suite-shard-legs.tsv` contains a row `plugins/soleur/scripts/run-health-emit.test.sh<TAB><N>` with `N` in `1..8` (the generator's leg choice; `2` expected per the incumbent table and #12650's identical regen).
- [ ] AC3 — Both `# generated-at=` headers are re-stamped by the generator run.
- [ ] AC4 — `bash scripts/test-all-corpus-weight-budget.test.sh` exits 0 and prints `ALL PASS`.
- [ ] AC5 — The PR's own CI run shows all `test-scripts (n/8)` legs green, including the previously red `3/8`.
- [ ] AC6 — `git diff origin/main...HEAD -- scripts/suite-durations.tsv scripts/suite-shard-legs.tsv` (merge-base diff, not the moving tip) contains only the new row(s) and `generated-at` header stamps — the generator reports `0 moved, 1 new, 0 no longer registered`; no hand-edited rows.
- [ ] AC7 — `scripts/suite-weight-exemptions.tsv` is untouched (floor weight needs no exemption).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — repo-internal CI/test-infrastructure change. Engineering's assessment question ("significant architectural decisions… beyond normal implementation") does not match: the architecture was decided by ADR-240 and this plan executes its prescribed maintenance path; no domain leader spawns warranted.

## Test Scenarios

- Given `run-health-emit.test.sh` is registered and untabled, when `python3 scripts/regenerate-shard-manifest.py --incremental --write` runs, then `suite-durations.tsv` gains `…1272<TAB>floor` and `suite-shard-legs.tsv` gains a leg row — `integration` (the generator's own dry-run verified this on 2026-11-11).
- Given the regenerated tables, when `bash scripts/test-all-corpus-weight-budget.test.sh` runs, then exit 0 with `ALL PASS` — `integration` (currently reds with exactly the named label; this is the reproduction).
- Given a sibling regen (#12650) lands on main first, when the branch syncs and the generator re-runs, then it reports `0 new` and the diff is empty — `integration` (merge-ordering edge; resolution = close as superseded, never hand-merge).
- Given the generator reports anything other than `0 moved, 1 new, 0 no longer registered`, when the diff is inspected, then the unexpected rows are not committed — `unit`-level discipline (stop, re-sync, re-run).

## Context

- Root cause, first half: PR #12565 registered `plugins/soleur/scripts/run-health-emit.test.sh` but did not run the shard-manifest regen; ADR-240 §3's hash-fallback kept the suite *runnable* (it ran in CI on a fallback leg) while the committed-weight gate correctly redded — the detection guard did its job.
- Root cause, second half (review-seat finding, verified 2026-11-11): the gate redded **on #12565's own PR CI before merge** — `test-scripts (3/8)` and the required `test` aggregate both concluded FAILURE ~21h pre-merge — yet the PR landed directly (merged by `deruelle`, no `merge_group` run) via the ruleset-14145388 bypass actors (`OrganizationAdmin`/`RepositoryRole`, `pull_request` mode). So the incident class is "missing regen **+ merge over a red required check**": the detection layer is enforced, the merge-enforcement layer is not, and the vector stays open for the next unrowed suite. Tracked separately — the enforcement gap is out of scope for this generated-data fix (see the deferred issue named in this PR's review synthesis).
- Fix priority: main is red, so this is a same-day un-blocking fix (`p1-high`).
- No exemptions needed: the floor weight 1272ms is far under the 600s `CORPUS_SUITE_CAP_MS`.
- Plan-review note: this plan ran inside a Task subagent of the one-shot pipeline (no subagent-spawn tool); the prescribed reviewer fan-out could not be spawned in-process — equivalent inline verification (live test run, generator dry-run, sibling-diff comparison, ADR read) substituted and is disclosed under `Reviewed-Coverage: sequential-fallback`.

## References

- ADR-240 — `knowledge-base/engineering/architecture/decisions/ADR-240-shard-assignment-is-checked-in-derived-data.md`
- Learning — `knowledge-base/project/learnings/2026-09-19-a-generated-artifact-in-my-diff-made-every-landing-on-main-a-conflict.md`
- Learning — `knowledge-base/project/learnings/2026-11-07-a-required-shard-on-its-timeout-edge-made-the-merge-queue-a-coin-flip.md`
- Sibling plan — `knowledge-base/project/plans/2026-11-10-feat-run-health-instrumentation-plan.md` (the PR #12565 plan)
- PR #12565 (merged, introduced the registration), PR #12650 (open, carries identical delta)
