---
title: "fix(ci): seed missing wallclock-p90 bound row for oracle-review-required"
type: fix
date: 2026-11-17
slug: fix-oracle-review-required-bound-row
branch: feat-one-shot-oracle-bound-row
issue: 12755
priority: medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(ci): seed missing wallclock-p90 bound row for oracle-review-required

## Enhancement Summary

**Deepened on:** 2026-11-17 (headless; no Agent/Task spawn available, so the
per-section research fan-out ran as inline verification passes — see
`## Deepen Pass` for gate verdicts and live re-verification).

**Key improvements:**

1. AC-4 corrected to merge-base diff form (`origin/main...HEAD`) and the
   pipeline-written artifact set enumerated exactly — `INDEX.md` is
   gitignored and can never appear in a diff.
2. Every load-bearing citation re-verified live: issue/PR states,
   #12329's file list (attribution), epic-goal constants at source
   (`GOAL_PR_S=1200`/`GOAL_MQ_S=900`), the parser contract at
   `watch-wallclock-p90-11774.sh`:125-159, both cited learnings, and both
   runbook section anchors.
3. One new consideration surfaced: no file-vs-file parity test binds the
   bounds TSV to `required-checks.txt` — the existing parity suites bind
   `required-checks.txt` to rulesets, a different edge. Recorded as a
   deferred technical row in `decision-challenges.md` (scope constraint
   forbids a script/test change in this PR).

## Overview

The `oracle-review-required` check became a required context in merged PR #12329
(2026-11-08, #10859 PR3b) but no bound row was added to
`scripts/required-check-wallclock-bounds.tsv` in the same change. Because a
required context with no bound row is itself a ratchet finding, every scheduled
run of `watch-wallclock-p90-11774.sh` exits 1 and reports
`unbound: oracle-review-required` on the standing tracker #12755 (epic #11556,
Lever E / #11774). This change seeds the missing row per the TSV header's own
documented method — measured p90 latency of the last ~30 completed+success
ci.yml runs per surface, rounded UP to the next minute, margin_frac 0.30 — and
records the seed where the file's own conventions require it.

## Problem Statement / Motivation

- Live defect confirmed by the instrument of record:
  `bash scripts/watch-wallclock-p90-11774.sh --dry-run` (run 2026-11-17 from a
  scratch dir against this worktree's files) exits 1 with flagged set =
  `- unbound: oracle-review-required — no row in scripts/required-check-wallclock-bounds.tsv`.
- The weekly `wallclock-p90-watch.yml` run goes red on this finding every week
  until the row lands; the standing tracker re-flags it each run.
- Measured by that same dry run (verbatim table values):
  `oracle-review-required | pull_request | n=30 | p50 35 | p90 139 | p90 dur 28`
  and `merge_group | n=29 | p50 27 | p90 100 | p90 dur 29`. Next-minute ceilings:
  PR 139 s → 180 s; merge queue 100 s → 120 s. Both bounds are ≥ the re-measured
  p90 as the TSV header requires, and comfortably inside the epic goals
  (PR ≤ 1200 s / merge queue ≤ 900 s).

## Proposed Solution

Insert one data row into `scripts/required-check-wallclock-bounds.tsv`, between
the `vendor-pin-required` row and the `cla-check` row (mirroring
`scripts/required-checks.txt`, where `oracle-review-required` sits between
`vendor-pin-required` and the CLA block):

```text
oracle-review-required<TAB>180<TAB>120<TAB>0.30
```

(TAB = literal tab byte; the row is 4 tab-separated columns, matching every
sibling row and the probe's bounds parser at
`watch-wallclock-p90-11774.sh` section (0b): NF==4, numeric fields, bounds > 0,
margin < 2, no duplicate check_name.)

Accompany it with the documentation the file's own conventions require:

1. A dated header-note line recording the seed (the file's convention — cf. the
   `UMBRELLA RE-SEED (2026-11-06, #12089)` note and "the rows raised at commit
   time are recorded in the bounds-TSV header note").
2. A measured-history bullet in
   `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
   (the runbook's "record the measurement that moved a bound here" convention).
3. A commit-time re-verification pass: re-run the dry run, confirm the flagged
   set no longer lists `unbound: oracle-review-required` AND that the re-measured
   p90 is still ≤ the seeded bounds; if drift pushed a p90 above a seed, re-seed
   that bound to the next-minute ceiling of the re-measured value (the header's
   own rule) and update the header note, runbook bullet, and this plan's numbers
   in the same commit.

## Technical Considerations

- **Population is derived, never enumerated.** The probe derives its required
  set from non-comment rows of `scripts/required-checks.txt`; `oracle-review-required`
  is already there (verified). No probe or test change is needed — adding the
  bound row is the complete fix.
- **No file-vs-file parity test exists.** Nothing in the test suite binds the
  TSV to `required-checks.txt`; the weekly probe is the only enforcement.
  `scripts/watch-wallclock-p90-11774.test.sh` exercises fixtures via the
  `WATCH_REQUIRED`/`WATCH_BOUNDS` env seams, never the committed files — no test
  updates needed. (Deepen-verified: `required-checks-canonical-parity.test.sh`
  and `required-checks-merge-group-coverage.test.sh` bind `required-checks.txt`
  to the ruleset canonicals/workflows — a different edge. A TSV↔population
  parity check would catch this class at PR time; deferred — the ask's scope
  constraint forbids a script/test change in this PR. See decision-challenges
  technical rows.)
- **Both surfaces measured.** The dry run reports qualifying samples on both
  surfaces (n=30 / n=29), so the row clears the finding outright — no
  `unmeasured` residual, no `stale bound` warning.
- **Whitespace discipline.** Sibling rows use single literal tabs. A space in
  `check_name` would be a different name entirely (the `skill-security-scan PR
  gate` row shows multi-word names are legal, but this name is single-word);
  a 5th column or a non-numeric field is a `cannot-establish` error (exit 3) in
  the probe, caught by the commit-time dry run.
- **Do not `Closes #12755`.** The tracker is the watch's standing report home
  and never auto-closes; a closing keyword in the PR body would kill the report
  surface on merge (learning
  `2026-11-15-byte-identical-row-is-not-a-clean-hunk-and-push-runs-carry-no-timings.md`
  documents this defect class twice in one session). Reference it contextually.
- **Merge-conflict surface.** A bound-row append is a one-line hunk; the
  2026-11-15 learning records a sibling TSV-row PR conflicting at the hunk level
  despite byte-identical values. Open-PR scan found no PR touching this file —
  re-check at ship time.

## Research Insights

**Premise validation (Phase 0.6, all held):**

- #12755 — OPEN, `ci-wallclock-p90: required-check wall-clock report` (the
  standing tracker; never auto-closes by design). Premise held.
- #11556 — OPEN, `epic: cut PR required-check time …` — contextual epic. Held.
- PR #12329 — MERGED 2026-11-08 (`feat(ci): S4 PR3b — required
  affected-index-ratchet + oracle-review-required context`). This is where the
  check became required without a bound row. Held.
- Cited paths verified on this branch: `scripts/required-check-wallclock-bounds.tsv`
  (60 lines, 12 bound rows), `scripts/required-checks.txt` (13 non-comment rows,
  including `oracle-review-required`), `scripts/watch-wallclock-p90-11774.sh`
  (probe; bounds parser at section (0b)).
- Cited issue #11774 — CLOSED (ratchet's own issue, already delivered); the
  unbound finding is the live residual.
- Collision pre-check: `gh pr list --search 12755` → none; `--search
  oracle-review-required` → none; per-file scan of all open PRs → none touches
  `scripts/required-check-wallclock-bounds.tsv`.
- ADR-corpus mechanism check: the proposed mechanism (a bound row in the
  committed TSV) is the file's own documented repair path — the TSV header and
  runbook both state a required check with no bound row is itself a finding and
  that bound-row removal is never the remedy. No ADR contradicts it.

**Property List (Phase 0.6b):**

1. `oracle-review-required` has a bound row → the weekly watch stops flagging
   `unbound` (observable: flagged set shrinks by exactly this finding).
2. Bounds are seeded from the measured baseline, rounded up to the next minute,
   margin 0.30 — and ≥ the commit-time re-measured p90.
3. The seed's measurement is recorded where the file/runbook conventions require
   it (header note + runbook measured history).

**Cut List (Phase 0.6b):**

- No mechanism in the ask was cut — the ask names exactly one mechanism (the
  bound row) and it is the minimal/only repair: the alternatives (remove the
  check from `required-checks.txt`; exempt it in the probe) are explicitly ruled
  out by the TSV header and do not exist as mechanisms respectively.
- Not added: probe code changes, test updates (no coverage binds the committed
  TSV), workflow changes — none buys a property in the list.

**Value-proposition measurement (Phase 0.6c):** the claimed saving is one weekly
red flag; measured: the dry run's flagged set is exactly 1 finding
(`unbound: oracle-review-required`) — after the row, zero.

**Institutional learnings applied:**

- `2026-11-15-byte-identical-row-is-not-a-clean-hunk-and-push-runs-carry-no-timings.md`
  — quote the dry-run output verbatim (done above); sibling-PR hunk conflicts on
  TSV rows; never emit a closing keyword against a standing tracker.
- `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md` —
  check names may contain spaces; this one does not; tabs delimit.
- Glossary: "ratchet" = pinned number moving only toward reduction — this row is
  a bound (may loosen only with runbook-recorded measurement), consistent.

**CLAUDE.md conventions:** plan filename `YYYY-MM-DD-<type>-<slug>-plan.md`;
kebab-case artifacts; conventional-commit title.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (spec dir created by this plan's Save
Tasks step). All spec-equivalent claims come from the brief itself and were
validated above: the unbound finding is live (dry run, exit 1), the measured
p90s match the brief exactly (139 s / 100 s), and no sibling PR touches the
file. Nothing to reconcile.

## User-Brand Impact

- **If this lands broken, the user experiences:** the weekly operator digest's
  checks-pipeline section keeps reporting the ratchet red — a noisy standing
  finding that can mask the next real breach.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  nothing user-facing — the diff is a CI-observability data row plus
  knowledge-base artifacts; no user data, credentials, or product surface is
  touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI-observability repair on a
  config data file; a wrong bound produces a red or a quiet weekly watch run,
  not a user-visible incident — `none`, not `single-user incident`.
- `threshold: none, reason: the touched paths are a CI-observability TSV and
  knowledge-base docs — no user-facing surface or regulated data`

## Observability

```yaml
liveness_signal:
  what: weekly wallclock-p90-watch verdict + standing tracker #12755 body
  cadence: weekly (Fri 09:07 UTC) + workflow_dispatch
  alert_target: operator digest §6 (reads tracker by ci/wallclock-p90 label)
  configured_in: .github/workflows/wallclock-p90-watch.yml
error_reporting:
  destination: standing tracker body + drift comments (issue #12755)
  fail_loud: "flagged findings list names offenders; exit 1 turns the workflow red"
failure_modes:
  - mode: "bound row malformed (wrong columns/non-numeric)"
    detection: "probe exit 3 cannot-establish; ::error:: names the row"
    alert_route: "weekly workflow goes red; tracker reports cannot-establish"
  - mode: "seeded bound drifts below real p90"
    detection: "breach finding when p90 > bound x 1.30"
    alert_route: "weekly workflow red + drift comment on flagged-set change"
logs:
  where: "GitHub Actions log of wallclock-p90-watch.yml; tracker issue body history"
  retention: "Actions retention window; tracker body rewritten each run"
discoverability_test:
  command: "grep -c '^oracle-review-required' scripts/required-check-wallclock-bounds.tsv"
  expected_output: "1"
```

## Open Code-Review Overlap

None — queried all open `code-review` issues (2026-11-17): no issue body names
`scripts/required-check-wallclock-bounds.tsv`, `scripts/required-checks.txt`,
or `scripts/watch-wallclock-p90-11774.sh`.

## Functional Overlap

No existing mechanism writes bound rows — the TSV is hand-edited per its header's
documented seeding method; `watch-wallclock-p90-11774.sh` reads it and the
workflow runs it. Direct file edit is the only path (agent-spawned
functional-discovery was unavailable in this process; verified inline by grep:
the only writers/readers of the file are the probe and its fixture tests).

## Implementation Phases

### Phase 1: Seed the bound row

- FR-1: Edit `scripts/required-check-wallclock-bounds.tsv` — insert
  `oracle-review-required<TAB>180<TAB>120<TAB>0.30` between the
  `vendor-pin-required` row and the `cla-check` row (position mirrors
  `required-checks.txt` ordering). Tabs must be literal tab bytes.
- FR-2: Same file — add a dated header-note line recording the seed
  (e.g. `# oracle-review-required seeded 2026-11-17: check went required via
  #12329 without a row; PR p90 139 s (n=30) / MQ p90 100 s (n=29) -> bounds
  180/120, margin 0.30`), placed with the other dated seed notes.
- FR-3: Append a measured-history bullet to
  `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  in the same dated style as the `2026-11-02 wallclock-p90 baseline` entry —
  seed values, n per surface, reason for the row (`unbound` finding, #12329).

### Phase 2: Commit-time verification (header-mandated)

- FR-4: Re-run `bash scripts/watch-wallclock-p90-11774.sh --dry-run` and
  verify: (a) the flagged set no longer contains
  `unbound: oracle-review-required`; (b) the row's bound columns read
  180/120 (no `—`); (c) re-measured p90 ≤ seeded bound on both surfaces. If a
  surface's p90 drifted above its seed, re-seed to the next-minute ceiling of
  the re-measured value and update FR-2/FR-3 numbers + this plan's recorded
  numbers in the same commit.
- FR-5: Confirm the diff touches only
  `scripts/required-check-wallclock-bounds.tsv` plus knowledge-base artifacts
  (plan, spec dir, runbook) — per the ask's scope constraint.
- PR body: reference #12755, #11556, #12329 contextually; NO `Closes #12755`
  (standing tracker must not auto-close); `## Changelog` section for the
  version-bump workflow.

## Files to Edit

- `scripts/required-check-wallclock-bounds.tsv` — +1 data row (+1 header comment line)
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` — +1 measured-history bullet

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-oracle-bound-row/tasks.md` (pipeline artifact)
- `knowledge-base/project/specs/feat-one-shot-oracle-bound-row/decision-challenges.md` (pipeline artifact)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add the missing bound row for required check `oracle-review-required` to `scripts/required-check-wallclock-bounds.tsv`" | FR-1 | mapped |
| 2 | "Seed per the file's own documented method in its header (bound = measured p90 of last ~30 completed+success ci.yml runs per surface, rounded UP to the next minute; margin_frac 0.30)" | FR-1, FR-4 | mapped |
| 3 | "Already measured 2026-11-17 via `scripts/watch-wallclock-p90-11774.sh --dry-run` from a scratch dir: pull_request surface p90=139s (n=30) → bound 180s; merge_group surface p90=100s (n=29) → bound 120s" | FR-1 values | mapped |
| 4 | "`watch-wallclock-p90-11774.sh --dry-run` flagged set no longer lists `unbound: oracle-review-required`" | AC-2, FR-4 | mapped |
| 5 | "row format matches sibling rows (tab-separated, 4 columns)" | AC-1, FR-1 | mapped |
| 6 | "only the TSV plus knowledge-base artifacts change" | FR-5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| FR-1 bound row | "add the missing bound row for required check `oracle-review-required` to `scripts/required-check-wallclock-bounds.tsv`" | asked |
| FR-2 TSV header seed note | — | inferred — justification: the file's own convention records seed corrections in a dated header note ("the rows raised at commit time are recorded in the bounds-TSV header note"; UMBRELLA RE-SEED precedent) |
| FR-3 runbook measured-history bullet | — | inferred — justification: the runbook states "record the measurement that moved a bound here"; a bound seed without the record leaves the file's provenance convention unmet |
| FR-4 commit-time re-verification | "Seed per the file's own documented method in its header" | asked — the header method includes re-verification against `--dry-run` at commit time |
| FR-5 diff-scope assertion | "only the TSV plus knowledge-base artifacts change" | asked |
| tasks.md / decision-challenges.md | — | inferred — justification: one-shot pipeline artifacts; both are knowledge-base files inside the ask's scope constraint |

### Split Assessment

- Subsystems touched: 2 — `scripts/` (first segment root), `knowledge-base/` (docs)
- Planned files: 4 | Estimated changed lines: ~25
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [x] AC-1: `scripts/required-check-wallclock-bounds.tsv` contains exactly one
  `oracle-review-required` row, between the `vendor-pin-required` and
  `cla-check` rows, of exactly 4 tab-separated columns
  (`oracle-review-required`, `180`, `120`, `0.30`) — literal tabs, all numeric,
  matching sibling-row shape.
- [x] AC-2: `bash scripts/watch-wallclock-p90-11774.sh --dry-run` flagged set
  does not list `unbound: oracle-review-required`, and the
  `oracle-review-required` table rows show bound columns 180/120 (not `—`).
- [x] AC-3: Each seeded bound is ≥ the commit-time re-measured p90 for its
  surface (TSV header contract); any drift-driven re-seed is recorded in the
  header note, the runbook bullet, and this plan in the same commit.
- [ ] AC-4: `git diff --name-only origin/main...HEAD` lists only
  `scripts/required-check-wallclock-bounds.tsv` plus knowledge-base artifacts —
  explicitly: this plan file,
  `knowledge-base/project/specs/feat-one-shot-oracle-bound-row/tasks.md`,
  `decision-challenges.md`, `session-state.md` (pipeline-written), and
  `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`.
  (`knowledge-base/INDEX.md` is gitignored — generated, never in a diff.)
  Merge-base form (`...`), not the two-dot `origin/main -- <paths>` form, so a
  sibling merge touching these paths does not false-red the assertion.
- [x] AC-5: A dated seed note documents the row's provenance in the TSV header
  block, and a measured-history bullet lands in
  `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`.
- [ ] AC-6: PR body contains no `Closes`/`Fixes`/`Resolves` keyword against
  #12755 (standing tracker; never auto-closes).

## Test Scenarios

- Given the edited TSV, when the probe's bounds parser predicate is applied
  (`awk -F'\t'` → NF==4, all-numeric fields, bounds > 0, margin < 2, unique
  check_name, check_name present in `required-checks.txt`), then the new row
  passes every predicate — `unit` layer (deterministic file-shape assertion).
- Given the committed row, when
  `bash scripts/watch-wallclock-p90-11774.sh --dry-run` runs against live data,
  then exit is 0 (or the flagged set contains no `oracle-review-required`
  finding of any class) — `integration` layer (the instrument of record, per
  the file's own commit-time verification convention).
- Given a hypothetical p90 drift above a seeded bound between plan and commit,
  when the FR-4 verification runs, then the row is re-seeded to the next-minute
  ceiling of the re-measured value before commit — `integration` layer
  (conditional re-seed arm; the header's own rule).
- Given the sibling-row position, when `git diff` renders the hunk, then only
  the new row (plus the header comment) appears — no accidental whitespace or
  reorder churn on neighbouring rows — `unit` layer.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI-observability data repair
(single TSV row + knowledge-base docs). Mechanical UI-surface override did not
fire: no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in
Files to Create/Edit.

## Skipped Gates (with rationale)

- **Network-outage checklist (1.4):** no trigger pattern in the feature
  description.
- **Community discovery (1.5) / external research (1.6b):** strong local
  context; the file documents its own method. Skipped.
- **GDPR (2.7):** no regulated-data surface; none of the (a)–(d) triggers.
- **IaC routing (2.8):** no new infrastructure; a data row in a committed file.
- **Task Design (2.9.3):** no new autonomous-task surface.
- **ADR/C4 (2.10):** no architectural decision — the bound-row requirement is
  already the system's documented contract.
- **Encryption Posture (2.11):** no persistent store or new connection.
- **Guard Contract (2.12):** deliverable is a data row consumed by an existing
  ratchet, not a new guard/gate/lint.
- **Founder check (2.13) / post-review gates:** headless pipeline context.

## Context

- Seeding method (TSV header): "bound = the measured p90 latency of the last
  ~30 completed+conclusion=success ci.yml runs per surface, rounded UP to the
  next minute; margin 0.30."
- The probe's bounds parser rejects malformed rows with exit 3
  (`cannot-establish`) — a wrong-column-count row turns the weekly run red
  harder than the finding it repairs; the FR-4 dry run is the verification of
  record.
- `issue: 12755` frontmatter is a pointer to the standing tracker, not a
  closure target; see AC-6.

## Sharp Edges

- Verify the inserted row uses literal TAB bytes — editors that expand tabs
  ship a row the parser splits into 1 column (exit 3). Assert with
  `awk -F'\t' '$1=="oracle-review-required"{print NF}'` expecting `4`.
- Re-check open PRs touching `scripts/required-check-wallclock-bounds.tsv` at
  ship time (TSV-row PRs conflict at the hunk level even on disjoint rows).
- Do NOT write `Closes #12755` anywhere (PR body, commit message, comments) —
  it would close the standing tracker that is the watch's report home.
- Quote the dry-run output verbatim when updating numbers; do not recollect.
- If the FR-4 dry run cannot reach the API at work time, treat as blocked, not
  green — the header's commit-time verification is part of the method.

## Deepen Pass

Recorded 2026-11-17. No nested-subagent capability in this harness (per
`2026-11-01-devin-subagents-cannot-spawn-nested-subagents`), so the skill's
fan-out ran as inline verification passes; the parent pipeline may still run
`soleur:plan-review` and the batched CTO consult downstream.

### Gate verdicts

| Gate | Verdict |
|---|---|
| 4.5 Network-outage | not triggered — no trigger pattern in the plan |
| 4.55 Downtime & Cutover | not triggered — TSV data row + docs only |
| 4.6 User-Brand Impact | PASS — section present, threshold `none`, no sensitive-path hit, scope-out reason present |
| 4.7 Observability | PASS — all 5 fields non-placeholder; probe verb `grep` is Check-10 allowlisted; `expected_output` is the literal `1`; no SSH, no banned metacharacters, sub-15 s |
| 4.8 PAT-shaped variable | PASS — zero hits on the 4-pattern sweep |
| 4.9 UI wireframe | not triggered — no UI-surface files |
| 4.10 Encryption posture | not triggered — no store/connection introduced |
| 4.11 Guard contract | not triggered — deliverable is a data row, not a guard |
| 4.12 Scope check | PASS — exactly 1 unfenced `## Scope Check`; 6 mapped asks; every `inferred` row justified; `Recommendation:` present |
| 4.13 Task design | not triggered — no autonomous-task surface |

### Claims re-verified live

- #10859 CLOSED, title `ci: S4 PR3b, make the affected-index ratchet a
  required context (held for the budget owner)` — `gh issue view`.
- #12329 MERGED; its file list contains `scripts/required-checks.txt` and
  `.github/workflows/ci.yml` — the attribution "became required via #12329"
  holds (`gh pr view 12329 --json files`).
- Epic goals read at source: `GOAL_PR_S=1200`, `GOAL_MQ_S=900`
  (`scripts/watch-wallclock-p90-11774.sh`:96-97) — seeded bounds sit far
  inside.
- Parser contract re-read at `watch-wallclock-p90-11774.sh`:125-159 — NF==4
  on the RAW line (`awk -F'\t'`), `^[0-9]+$` bounds >0,
  `^[0-9]+(\.[0-9]+)?$` margin <2, duplicate-name reject, stale-bound
  warning, `unbound` finding at :281. The plan's parser claims match.
- Ordering verified: bounds TSV `vendor-pin-required` (:58) → `cla-check`
  (:59); `required-checks.txt` `vendor-pin-required` (:274) →
  `oracle-review-required` (:294) → `cla-check` (:297). Placement mirrors.
- Counts re-measured: 12 TSV data rows, 13 non-comment population rows.
- Runbook anchors exist: `## The wall-clock ratchet` (:189),
  `## Measured history` (:287); the `2026-11-02 wallclock-p90 baseline`
  bullet (:371) is the dated-bullet precedent FR-3 mirrors.
- `discoverability_test.command` executed once: prints `0` pre-edit as
  designed (post-edit target `1`).
- Rule-id citations in the plan body: none — nothing to check against the
  active/retired registries.

### Verify-the-negative + self-audit

- "No parity test binds the TSV" — confirmed: the only repo readers of
  `required-check-wallclock-bounds.tsv` are the probe and
  `wallclock-p90-watch.yml` (plus KB docs). The two `required-checks-*`
  parity suites bind `required-checks.txt` to ruleset canonicals/workflows,
  not to the bounds file.
- "No `stale bound` warning" — the row's name is a non-comment population
  row (:294), so the warning predicate at :159 cannot fire.
- Post-edit self-audit: no symbols, files or fixtures are dropped or
  renamed — trivially clean.

### Precedent-diff (§4.4)

Sibling data rows are uniform `<name>\t<int>\t<int>\t0.30` and dated
`#`-header notes (UMBRELLA RE-SEED, :36) are the seed-note precedent — the
new row and note mirror the canonical forms; no precedent divergence.

## References

- Standing tracker: #12755 · Epic: #11556 · Ratchet issue: #11774 · Requiring
  PR: #12329 · Oracle-check issue: #10859
- `scripts/required-check-wallclock-bounds.tsv` header (columns + seeding method)
- `scripts/watch-wallclock-p90-11774.sh` bounds-table parser, section (0b)
- Runbook: `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`
  §The wall-clock ratchet · §Measured history
