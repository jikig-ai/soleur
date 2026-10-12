---
title: Path-aware CI gating — un-park S4 (affected-only PR runs) plus two adjacent fixes
date: 2026-10-12
issue: 9729
related_issues: [9721, 9307, 9323, 9730, 9818]
related_adrs: [ADR-262, ADR-270, ADR-276, ADR-183, ADR-217]
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: path-aware CI gating

## What We're Building

Doc-only and other low-blast-radius PRs stop consuming the full CI battery on `pull_request`, freeing hosted
runners (60-concurrent account cap) for the rest of the pipeline. Trigger: PR 10097 (one markdown file,
`knowledge-base/project/weakness-digest.md`) ran roughly the whole battery.

Operator decision: **un-park S4 (#9729)** — PR runs execute the `--affected` suite set plus the always-on
ratchets; `merge_group` and push-to-main keep the full battery. Two adjacent fixes ride along:

1. **e2e classifier fallback bug.** On PR 10097 the `e2e` job annotated `applicable=true` /
   `enum-failed (diff unresolvable or classifier absent on base ref)` and ran the heavy path although
   `scripts/ci-e2e-classify.sh` is designed to skip `knowledge-base/**`. Root cause not yet established.
2. **Gate `shard-totality-mutations` (3 legs, ~10.7 job-min per PR run).** Unconditional, not in the `test`
   aggregator's `needs`, ADR-262-style path gate, no aggregator change.

## Why This Approach

- `knowledge-base/**` is **not** safely skippable by path alone: `scripts/test-affected-kb-consumers.baseline.txt`
  has 240 rows of real reads (ADRs, registers, roadmap, runbooks, `model.likec4.json`, `vision.md`, specs JSON),
  and `test-affected-paths.sh` has a content-keyed whole-tree scan. A naive docs-only skip is a hole. The
  repo's own affected selector already encodes the truth, so S4 (selector-driven) beats a hand-written path list.
- Workflow-level `paths-ignore` is rejected: required contexts (`test`, `e2e`, ~20 more in
  `scripts/required-checks.txt`) would never report and wedge every PR. Synthetic statuses are rejected by
  ADR-276 Decision 4. Mechanism stays job-level `if:` + a named skip-reason tolerance in the `test` aggregator.
- ADR-270 (merge queue) is `accepted`, so ADR-276 3(h) is satisfied; the merge_group candidate run is the
  enforced full-battery gate, so a reduced PR run no longer has to be the last line of defence.
- Measured (2026-10-07, ADR-276): affected selection picks 27% (docs diff) of 79.0 suite-minutes; about 23
  suite-minutes off a PR `test-scripts` run. PR 10097 head run: >= 60 job-min completed (lower bound, 8
  `test-scripts` legs unfinished at measurement); latest full PR baseline 164.4 job-min, 119.2 of them
  `test-scripts`. ~14% of the last 300 merged PRs were `knowledge-base/**/*.md`-only.

## Key Decisions

| Decision | Choice |
|---|---|
| Scope | Un-park S4 (#9729), not a narrow docs-only path list, not quick-wins-only |
| S4 re-decide gate (S2 #9818 and S3 censuses first) | **Waived by the operator, 2026-10-12.** Reason: the waste is live; S4's evidence is a replay (`--print-selection` over the last 300 first-parent commits vs suite failures, escape rate under 2%), independent of the S2/S3 censuses. Kill-switch and merge_group full battery stay. |
| Admin-merge residual (S4 entry gate 2) | **Detective post-merge probe**: flag any merge whose head SHA lacks a completed full-battery `[full]` CI run; plus `admin-merge-ready.sh` marker check for agents. Bypass actors unchanged. Counted in the escape metric. |
| Adjacent in scope | e2e classifier fallback bug; `shard-totality-mutations` path gate |
| Adjacent as tracked follow-ups | CodeQL/Code Quality on md-only PRs (~10.6 job-min on PR 10097; owned by S5 #9730, needs CLO/CTO decision); `claude-code-review.yml` has no path/actor gate (LLM cost, unmeasured) |
| Mechanism | Job-level `if:` + `test` aggregator tolerates skip only for named reasons (`pull_request` event, switch `on`, gated legs only); `encryption-posture` still required to pass; fail closed on any unknown |
| Kill-switch | Repository variable, exactly `on` (ADR-276 3(c)); rollback = unset |
| Authority | `merge_group`, push, `workflow_dispatch`, schedule, undeterminable diff, runner edit keep the full battery |
| Productize candidate | none (one-off CI lever) |

Inherited from #9729 unchanged: `[full]` `run-name` suffix on full-battery runs; the "runner changed means
full battery" detector and the affected-selection index are read from a trusted base-ref copy; the
registration-only carve-out stays out of PR mode; ADR-276 amendment plus pointer amendments to ADR-262 and
ADR-183; own Guard Contract in its plan.

## User-Brand Impact

- **Artifact:** the required `test` aggregator context and the PR CI battery (`.github/workflows/ci.yml`,
  `scripts/test-all.sh`, `scripts/lib/test-relevance-paths.sh`).
- **Vector:** a reduced PR run reads green and lets a regression through; a user-facing regression ships to
  production before the merge_group or post-merge run catches it (or never, on an `--admin` merge).
- **Threshold:** `single-user incident`.

## Open Questions

- Root cause of the e2e `enum-failed` fallback on PR 10097 (log endpoint returned empty; locally
  `origin/main:scripts/ci-e2e-classify.sh` exists and the diff resolves). Plan must reproduce before fixing.
- `--print-selection` timed out at 120 to 170 s locally; the replay harness must run in CI or with a bounded
  selector, and the 86 s pre-pass must run once per run, not per shard leg.
- Which exact `test`-aggregator skip reasons to tolerate, and the `battery-owed.sh`, deploy `workflow_run`
  and `post-merge-monitor.yml` consumers that must never read a reduced run as full (ADR-276 3(a)).
- Whether the always-on live scanners inside `test-scripts` (`lint-rule-bodies-live`,
  `lint-legal-registers-live`, `generate-kb-index-live`) are in the always-on ratchet set under S4.
- `claude-code-review.yml` cost and a gate design (follow-up, out of scope).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** CTO (verified against the repo): job-level `if:` plus a named tolerance in the aggregator is the
only mechanism that keeps every required context reporting; the safe KB path set must be derived from the
selector and the 240-row baseline, not asserted; build as an ADR-276 stage amendment, not a quiet standalone
edit; ranked other levers: shard-totality gate, `test-scripts-heavy` and `web-platform-build` following the
same classifier, CodeQL via S5. Legal, marketing, sales, finance, product and support: no implications for an
internal CI lever (assessment-only, no leaders spawned).

## Capability Gaps

None reported.
