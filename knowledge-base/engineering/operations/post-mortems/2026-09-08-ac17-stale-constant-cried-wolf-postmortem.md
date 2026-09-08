---
title: "AC17's hardcoded count cried wolf on three healthy Sentry applies, silencing the probe that would have proved them healthy"
date: 2026-09-08
incident_pr: 7866
incident_window: "2026-09-06T14:38Z .. 2026-09-08T09:00Z"
recovery_at: "2026-09-07T16:39Z (assurance recovered out-of-band); 2026-09-08 (cause fixed)"
suspected_change: "72ebe67b7 (#7821) — AC17 shipped asserting a literal 2 surviving sentry_issue_alert resources while the same commit declared 3"
brand_survival_threshold: aggregate pattern
status: RESOLVED
triggers:
  - ci/apply-sentry-infra required-job failure on main
  - auto-filed p1 tracker #7865 instructing the operator to assume a partial write
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal data was accessed, altered, or disclosed. This was a CI assertion defect over Terraform state metadata (resource address counts); live Sentry paging rules were verified unchanged (27 sentry_alert + 3 sentry_issue_alert, AC19/AC20 field-for-field PASS) throughout the window."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

The `Apply sentry infra` job on `main` failed on three consecutive merges (2026-09-06 `72ebe67b7`, 2026-09-07 16:34 `0341b8a8f`, 2026-09-07 17:58 `8ce4ec7d6`). Each time the apply itself **succeeded** and live Sentry paging state was correct; what failed was AC17, the step that decides whether a failed apply was a PARTIAL adoption of the 27 migrated paging rules.

AC17 asserted a hardcoded `27` and `2`. The correct value was `27` and **`3`** — and it was wrong **on arrival, not stale**: `git_data_boot_warning` landed in `0f39b7aa2` (PR #7805, `Refs #7772`) two days _before_ the commit that wrote the `2`, whose own message counts three while its gate asserts two.

## Status

RESOLVED. AC17 now derives both expectations from the `.tf` and compares address SETS; the assurance probes it was silencing now carry `always()`.

## Impact

No user-facing impact and no personal-data impact. The damage was to **assurance and to operator trust in the signal**:

1. **The compensating probe was silenced exactly when it mattered.** `sentry_alert live fidelity (AC19/AC20)` — the only check that reads all 27 rules field-by-field against the committed capture — carried no `if:`, so it inherited an implicit `success()` and was **skipped** on every one of the three runs. Verified from the API on run `34149741385`: step 14 `failure`, step 15 `skipped`.
2. **A p1 told the operator the opposite of the truth.** The `if: failure()` filer opened #7865 (`priority/p1-high`) whose body reads _"assume a partial write"_ and _"must show 27 `sentry_alert.` and 2 `sentry_issue_alert.` addresses … Anything else is a partial adoption and the highest-priority thing in the repo"_. `byok-art-33-breach` is among the 27, so the message implied the GDPR Art. 33 detector might be dark. It was not.
3. **Assurance was recovered out-of-band, not by the pipeline.** A `scheduled-sentry-alert-drift.yml` dispatch (run `34144160724`) reported `sentry_alert live fidelity: PASS (all 27 in-scope rules match the committed capture field-for-field)`.

## Timeline

| When (UTC) | Actor | Event |
|---|---|---|
| 2026-09-04 16:40 | agent | `0f39b7aa2` (#7805) adds `git_data_boot_warning`, making it 3 `sentry_issue_alert` |
| 2026-09-06 14:38 | agent | `72ebe67b7` (#7821) ships AC17 asserting `2`; its own commit body counts three |
| 2026-09-06 14:39 | agent | First red. #7865 auto-filed as p1 "assume a partial write" |
| 2026-09-07 16:36 | agent | Second red (`0341b8a8f`); tracker re-commented |
| 2026-09-07 16:39 | agent | Drift dispatch `34144160724` confirms live fidelity PASS — assurance recovered out-of-band |
| 2026-09-07 17:59 | agent | Third red (`8ce4ec7d6`) |
| 2026-09-08 | agent | Cause fixed in #7866; AC19/AC20 + BYOK liveness given `always()` |

## Root cause

A number invented at authoring time, in a file whose contents move underneath it — asserted as an exact equality, in a gate whose failure message declares a paging emergency.

Three aggravating factors turned one wrong constant into a silenced probe and a false p1:

1. **The gate's expectation was a literal, not a derivation.** Nothing tied `2` to the `.tf` that produces the state.
2. **The dependent probe was on an implicit `success()`.** AC17 exits 1, so every downstream step without a status function is skipped — including the one that would have proved the apply healthy. The workflow's own comment already documented this exact hazard for a sibling step ~90 lines above; the lesson was written down and not applied to AC17.
3. **Nothing pinned the assertion.** Reverting the derivation to the literals left every suite in the repo green. The only thing that ever caught the wrong `2` was three live applies reding on `main`.

## What went well

- The `if: failure()` filer routed the failure to a labelled, deduped tracker instead of leaving it as a red run in a workflow list.
- The scheduled drift probe was a genuinely independent second source and produced the correct all-clear.
- The apply's own safety argument held: `0 changed, 0 destroyed`, matching the PR's `plan_pr` prediction exactly.

## What went wrong

- A gate that cries partial-adoption on a healthy apply is worse than no gate: it is the false alarm that teaches an operator to skip the one message meaning the 27 paging rules really are half-moved.
- The failure text was **operator-facing and wrong**, and it survived the first fix attempt — correcting the gate while leaving the runbook body moves the false alarm rather than removing it.

## Corrective actions (all landed in #7866)

- AC17 derives both expectations from the `.tf`, with a non-vacuity floor on `sentry_alert` (deliberately none on `sentry_issue_alert` — zero is the migration's intended end state).
- AC17 compares sorted address SETS, so an orphan paired with a compensating rename no longer nets to zero. The step's `name:` promise of "no orphan" is now true, and the error names which addresses diverge.
- All five stale "27 + 2" restatements deleted rather than updated — including the filer's issue body, which is what an operator reads mid-incident. Any literal there re-acquires the same rot.
- `always()` on `sentry_alert live fidelity (AC19/AC20)` and on the BYOK Art. 33 liveness assertion, so an AC17 failure can no longer silence them.
- New `tests/scripts/test-sentry-ac17-derived-counts.sh` (10 rows) executes the step's own bytes extracted from the shipped YAML under `bash -e`. Restoring the hardcoded `2` reds 3 rows.
- `T13` in `test-sentry-full-root-apply.sh` — the repo's existing gate for the unbracketed-status-capture class — widened from the bare-command shape to `VAR=$(...)`, helper definitions, and backslash-continued lines. It had been blind to all four such lines in AC17.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
