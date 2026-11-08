---
title: "docs: Record post-corroboration criterion-a re-run and ejections-listing residual in S4 activation runbook"
type: docs
date: 2026-11-08
slug: docs-runbook-ejections-residual
branch: feat-one-shot-12428-runbook-ejections-residual
issue: 12428
closes: 12428
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# docs: Record post-corroboration criterion-a re-run and ejections-listing residual in S4 activation runbook

Track #12428 — the residual of #10862 (closed via merged PR #12377): the `ejections`
phase's `?event=merge_group&created=…` window listing is the same search-index class as
the `?head_sha=` listing whose drops PR #12377 corroborated, and its `total_count`
self-check cannot see a dropped run. This change is documentation-only: two prose
additions to `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
— (1) a dated 2026-11-08 entry in §2 "Where things stand" recording the fresh-window
criterion-a evidence re-run that ran after the `ci_runs` corroboration fix shipped
(300 commit units / 82 ejection units on window 2026-10-29T06:39:56Z..2026-11-08T04:43:01Z,
computed=NO-GO on the bound arm, driven by the not-evaluable bucket, not dropped runs);
and (2) a limits-list bullet in §4 recording the ejections-side residual (silent
under-count biases the cp95 bound toward a false GO; recorded-not-built per the
2026-11-08 CTO ruling, decision-challenges.md row 4 of the archived #10862 spec dir).
Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-08
**Sections enhanced:** Scope Check (verbatim ask rows, conventions ask added), this section
**Research agents used:** none — `Reviewed-Coverage: sequential-fallback` (no Task/subagent
spawn in this harness; the deepen halt gates and review lenses ran inline in the pipeline
runner and are disclosed as such, matching the archived #10862 spec's precedent).

### Key Improvements

1. Ask Mapping quotes tightened to verbatim substrings of the brief; the
   "keeping the file's existing dated-ledger and limits-list conventions" ask is now
   mapped to Phases 1–2 and AC5.
2. Deepen halt gates verified: 4.6 User-Brand Impact (present, threshold `none`, no
   sensitive-path match), 4.7 Observability (pure-docs skip), 4.8 PAT-shaped variables
   (no hits), 4.9 UI wireframe (no UI surface), 4.10 Encryption Posture (no
   store/connection), 4.11 Guard Contract (no guard deliverable), 4.12 Scope Check (one
   unfenced compliant section), 4.13 Task Design (no new autonomous task).
3. Every statistic re-verified verbatim against `receipts/rerun/replay-summary.txt` and
   `receipts/rerun/histograms.txt` — including the 58-of-382 not-evaluable split (57
   ejection units + 1 commit unit) the brief elides.

### New Considerations Discovered

None — premise, receipts, conventions and ledger placement all verified at plan time;
the deepen pass surfaced no additional defects or asks.

## Research Insights

**Relevant files:**

- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` — the
  only edit target. §2 "Where things stand" ends at `## 3.` (line 74); its ledger
  convention is a dated `- YYYY-MM-DD:` bullet (the 2026-11-07 entry at lines 66–72).
  §4's limits list opens at line 127 ("Read the output with these limits in mind") and
  ends before `## 5.` (line 145); the head_sha residual sentence lives inside the
  `no-run` bullet (lines 135–143).
- `knowledge-base/project/specs/archive/20261108-110953-feat-one-shot-10862-norun-investigation/receipts/rerun/`
  — `replay-summary.txt` (authoritative numbers), `histograms.txt` (bucket
  composition), `commands.txt` (commands + rc), `README.md` (verdict framing).
- `knowledge-base/project/specs/archive/20261108-110953-feat-one-shot-10862-norun-investigation/decision-challenges.md`
  — row 4 is the recorded-not-built CTO ruling this plan cites.

**Premise validation (Phase 0.6):** #12428 is OPEN and its body matches the brief
(ejections listing residual, `total_count` blind spot, re-evaluation criteria);
#10862 is CLOSED via merged PR #12377 (`mergedAt: 2026-11-08T17:35:29Z`, title
"fix(scripts): corroborate empty head_sha run listings via commit-keyed check-runs").
The runbook exists on `origin/main` and is markdown-lint clean (`bash
scripts/markdown-lint.sh` → `1 file(s) clean`). Receipts verified on disk; every
statistic in this plan was re-read from `replay-summary.txt` and `histograms.txt`,
not the brief (see reconciliation below). `collision-precheck.sh 12428` reported one
open PR naming the issue — #12430, the auto-draft on THIS branch (headRefName
`feat-one-shot-12428-runbook-ejections-residual`), not a foreign duplicate. Foreign
`test-all.sh` processes belong to unrelated sibling worktrees.

**Property List (Phase 0.6b):** (P1) §2's dated ledger records the 2026-11-08
criterion-a re-run at receipt granularity. (P2) The ledger conveys that the bound is
driven by classifier coverage, not dropped runs. (P3) §4's limits list records the
ejections-side residual and its false-GO bias. (P4) Nothing else changes — no code,
tests, workflows, or activation steps. **Cut List:** none — the ask names two prose
additions and the runbook is the canonical ledger location (grep confirms no other
ops doc carries this series' ledger).

**Research Reconciliation — Spec vs. Codebase:**

| Spec/brief claim | Reality (receipts) | Plan response |
|---|---|---|
| "unclassified jobs rule-body-lint/adr-ordinals/affected-index-ratchet/harness-discovery/grok-fidelity/cla-check/test-scripts" | `histograms.txt` classes affected-index-ratchet and test-scripts as `unsettled-jobs`, not `unclassified-job`; rule-body-lint/adr-ordinals/harness-discovery/grok-fidelity/cla-check are `unclassified-job` | Ledger entry names both route classes separately, matching the histogram |
| brief's not-evaluable enumeration | Combined `not-evaluable` is 58 of 382 = 57 ejection units + 1 commit unit (`unsettled-jobs: test-webplat (2/2)`), not 58 ejection units | Ledger says "58 of 382" over the combined population |
| Ledger convention | 2026-11-07 entry: one dated bullet, parenthesized compact stats, receipt path cited | New entry mirrors that shape and density |

**Institutional learnings applied:**

- `2026-10-28-my-new-runbook-sentence-about-the-gate-was-false…` — every added
  sentence is re-derived against `replay-summary.txt`/`histograms.txt`, and
  negative claims name the granularity the instrument proves (criterion a only).
- `2026-09-20-the-ops-only-green-verdict-claimed-a-fact-the-gate-never-measured.md`
  — the entry states criteria b/c/d `unmeasured` and the re-ruling operator-reserved;
  no wording implies a full re-ruling ran.
- Sharp edges: AC greps are scoped to the runbook file (the plan quotes the same
  tokens — a repo-wide grep would self-match); verification commands below were run
  once now (lint clean; `2026-11-08` count currently 0; anchors at lines 58/127/145);
  decision-challenges rows follow the machine-gated `Ruled by CTO agent, <date>:`
  shape with the exact `| Item | Class | Ruling |` header.

**External research:** skipped — docs-only change with receipts and conventions on
disk; nothing external to check (Phase 1.6).

**Functional overlap (Phase 1.5b, inline — no spawn capability):** only the target
runbook mentions the ejections residual or `merge_group` window listing under
`knowledge-base/engineering/operations/`; #12428 appears nowhere else in
`knowledge-base/`. No sibling doc to keep in sync.

**SpecFlow (Phase 3):** not invoked — the diff is two prose insertions with no user
flow, conditional logic, or state machine to enumerate; edge cases were checked
inline instead (stats vs. receipts, bullet placement inside existing lists, markdown
list formatting via the repo linter).

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrong statistic or a missing
  caveat in `ci-pr-affected-activation.md` §2/§4 — the dated ledger a future
  evidence re-run and go/no-go re-ruling reads from.
- **If this leaks, the user's [data / workflow / money] is exposed via:** an
  understated completeness residual that biases a future `CI_PR_AFFECTED` GO
  decision — workflow exposure (wrong activation evidence), not data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI runbook prose — no
  user-facing artifact changes, and the no-sensitive-path regex does not match
  `knowledge-base/engineering/operations/runbooks/`.

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` —
  two additions only (append-style bullets; zero lines removed).

## Files to Create

None (pipeline planning artifacts under `knowledge-base/project/specs/<branch>/` are
workflow bookkeeping, not deliverables).

## Implementation Phases

### Phase 1 — §2 dated ledger entry

Append one `- 2026-11-08:` bullet at the end of the §2 ledger (immediately after the
2026-11-07 bullet, before `## 3. Entry condition…`), mirroring the existing entry's
shape. Proposed text (re-derived from `receipts/rerun/replay-summary.txt`,
`histograms.txt`, `README.md`):

> - 2026-11-08: criterion a re-run on a fresh window after the `ci_runs` corroboration
>   fix (PR #12377) shipped — 300 commit units (298 clean / 1 rule-irrelevant / 1
>   not-evaluable) and 82 ejection units on window
>   2026-10-29T06:39:56Z..2026-11-08T04:43:01Z (421 merge_group runs seen, 82
>   refused). `computed=NO-GO reason=criterion-failed` on the bound arm:
>   attributable=0/382, unverified_as_escape=2/382 (point 0.52%, passes the ≤ 2%
>   leg), worst_case=60/382, cp95_upper_on_worst_case=19.10% ≥ the 12% bar. Every
>   commit unit resolved `runs_via=head-sha` (300/300, no index drop this window), so
>   the corroboration path was not exercised by a live drop here and the bound is now
>   driven by the not-evaluable bucket (58 of 382 — dominated by unclassified
>   rule-body-lint (20) and unsettled test-webplat legs (20 incl. the 1 commit
>   unit), with failed-job-without-fail-line (5), unclassified adr-ordinals (4),
>   harness-discovery/grok-fidelity (4), cla-check (1), and unsettled
>   affected-index-ratchet (2) and test-scripts (2)) plus 2 unverified — not by
>   dropped runs: the fix for criterion-a pressure is classifier coverage, not more
>   reads. Criteria b/c/d stayed `unmeasured` (the run measured criterion a only);
>   the go/no-go re-ruling and `CI_PR_AFFECTED` activation stay operator-owned.
>   Receipts: `knowledge-base/project/specs/archive/20261108-110953-feat-one-shot-10862-norun-investigation/receipts/rerun/`.

### Phase 2 — §4 limits-list sibling bullet

Append one bullet at the end of the §4 limits list (after the `no-run` bullet that
ends "…under-counting, not over)", before `## 5. The four criteria…`). Proposed
text:

> - The ejections window listing `?event=merge_group&created=…` is the same GitHub
>   search-index class as `?head_sha=`, and its `total_count` self-check cannot see a
>   dropped run — the count is index-computed from the same listing. A refused run
>   the index dropped is absent from both the ejections file and the window count,
>   so the refused-merge_group population can be silently under-counted; the
>   ejections are the only population that can hold an escape, so an under-count
>   biases the cp95 bound toward a false GO. Tracked as #12428; recorded-not-built
>   per the 2026-11-08 CTO ruling (`decision-challenges.md` row 4 of the archived
>   #10862 spec dir), because no per-sha non-search read exists to pin a window
>   listing against.

### Phase 3 — Verify

Run each AC command (below) plus `git diff --check`. No test suite is implicated —
the diff is prose in a runbook, and markdown-lint is the file's only mechanical gate.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "In §2 "Where things stand": add a dated 2026-11-08 entry recording the fresh-window criterion-a evidence re-run that ran after the ci_runs corroboration fix shipped" | Phase 1 / Files-to-Edit entry | mapped |
| 2 | "Extend it or add a sibling bullet recording the ejections-side residual" | Phase 2 / Files-to-Edit entry | mapped |
| 3 | "Docs-only runbook edit — no code, tests, or workflow changes" | AC5 (append-only, single-file diff) | mapped |
| 4 | "Still nothing activated; the go/no-go re-ruling and CI_PR_AFFECTED activation stay operator-owned" | Phase 1 proposed text + AC6 | mapped |
| 5 | "Two additions, keeping the file's existing dated-ledger and limits-list conventions" | Phases 1–2 proposed text (dated bullet, sibling bullet) + AC5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| §2 ledger bullet (Phase 1) | asks 1, 5 | asked |
| §4 residual bullet (Phase 2) | asks 2, 5 | asked |
| AC5 append-only / single-file guard | asks 3, 5 | asked |
| AC6 operator-ownership assertion | ask 4 | asked |
| Verification greps + markdown-lint (Phase 3) | — | inferred — justification: the runbook's only mechanical gate is markdown-lint; receipt-token greps are the check that keeps added sentences true (learnings above) |

### Split Assessment

- Subsystems touched: 1 — `knowledge-base/`
- Planned files: 1 | Estimated changed lines: ~20
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `awk '/^## 2\./,/^## 3\./' knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md | grep -c '2026-11-08'` returns >= 1, and the same region `grep -c 'cp95_upper_on_worst_case=19.10%'` and `grep -c 'computed=NO-GO'` each return >= 1.
- [ ] AC2 — `awk '/Read the output with these limits/,/^## 5\./' knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md | grep -c '#12428'` returns >= 1, and the same region `grep -c 'merge_group'` returns >= 1.
- [ ] AC3 — every statistic in the new §2 entry matches the receipts verbatim: `grep -F 'worst_case=60/382 cp95_upper_on_worst_case=19.10%' knowledge-base/project/specs/archive/20261108-110953-feat-one-shot-10862-norun-investigation/receipts/rerun/replay-summary.txt` exits 0 AND `grep -c '60/382'` on the runbook returns >= 1.
- [ ] AC4 — `bash scripts/markdown-lint.sh knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` prints `clean` (baseline verified clean 2026-11-08).
- [ ] AC5 — append-only single-file diff: `git diff origin/main...HEAD -- knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md | grep -cE '^-[^-]'` returns 0, and `git diff --name-only origin/main...HEAD | grep -v -e '^knowledge-base/project/' -e '^knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md$' | wc -l` returns 0.
- [ ] AC6 — the new §2 entry states the re-ruling stays operator-owned: `awk '/^## 2\./,/^## 3\./' knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md | grep -c 'operator'` returns >= 2 (the 2026-11-07 entry already carries one).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — documentation-only change to an internal CI
runbook; no UI-surface file in the diff, so the mechanical Product override does not
fire (assessed all 8 domains against `brainstorm-domain-config.md`).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 issues) contains no
mention of `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`.

## Test Scenarios

Docs-only — the "test" surface is the file's mechanical gate plus the receipt-token
greps in the ACs:

- Given the edited runbook, when `bash scripts/markdown-lint.sh` runs on it, then it
  reports clean (integration — repo's own linter).
- Given the committed receipts, when each statistic in the new ledger line is grepped
  verbatim against `replay-summary.txt`/`histograms.txt`, then each exists (unit-level
  content assertion — the false-claim class the learnings above name).

## Context

- The §4 residual is **recorded, not fixed**: the 2026-11-08 CTO ruling (archived
  #10862 spec dir, `decision-challenges.md` row 4) chose record-over-build because no
  per-sha non-search read exists to pin a window listing against. #12428's
  re-evaluation criterion — reopen before the next §4 evidence re-run feeds the
  go/no-go re-ruling — stands after this PR closes it.
- Nothing in this change re-runs evidence, re-rules the verdict, or touches
  `CI_PR_AFFECTED`; those stay operator-owned (#10448 / ADR-276 amendment).

## References

- Issue: #12428 (residual record); prior: #10862 (closed by merged PR #12377), #10448
- Receipts: `knowledge-base/project/specs/archive/20261108-110953-feat-one-shot-10862-norun-investigation/receipts/rerun/`
- Ruling: `knowledge-base/project/specs/archive/20261108-110953-feat-one-shot-10862-norun-investigation/decision-challenges.md` row 4
- Decision records this session: `knowledge-base/project/specs/feat-one-shot-12428-runbook-ejections-residual/decision-challenges.md`
