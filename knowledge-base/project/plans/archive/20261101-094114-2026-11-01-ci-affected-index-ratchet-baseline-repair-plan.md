---
title: "ci: repair affected-index-ratchet — stale accept row + two live gap pairs on main"
type: fix
date: 2026-11-01
slug: ci-affected-index-ratchet-baseline-repair
branch: feat-one-shot-11771-ratchet-baseline
issue: 11771
closes: 11771
---

# ci: repair affected-index-ratchet — stale accept row + two live gap pairs on main

The advisory `affected-index-ratchet` CI job (`continue-on-error`, `.github/workflows/ci.yml`
job at `affected-index-ratchet`) is red on every head: `SOLEUR_PR_AFFECTED_RATCHET exit=1
reason=stale-accept live=1512 baseline=1510` reproduced locally on this branch. Two live
gap pairs are uncovered and one accept row is stale. This plan repairs the baseline state
with the ratchet's own two remedies — declared edge for a real read, anchor-keyed accept
row for a mention — per the runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
("Ratchet red because main moved"). No new machinery is added.

## User-Brand Impact

- **If this lands broken, the user experiences:** no end-user artifact — the check gates
  Soleur's own PR flow. Worst case: the advisory check stays red or a declared edge selects
  one extra cheap suite on a rare docs edit.
- **If this leaks, the user's [data / workflow / money] is exposed via:** not applicable —
  no user data surface is touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** CI-selection machinery and accept-row bookkeeping;
  the blast radius is reviewer-facing signal quality, not a user-facing surface.

*Scope-out override:* `threshold: none, reason: the diff touches only CI-selection
declarations and an accept-row table — no user-impacting path.`

## Observability

```yaml
liveness_signal:
  what:            affected-index-ratchet check conclusion on pull_request/merge_group runs
  cadence:         per-PR / per-queue-entry
  alert_target:    PR check list (advisory; the soak tracker #10865 watches the window)
  configured_in:   .github/workflows/ci.yml (affected-index-ratchet job)

error_reporting:
  destination:     GHA job log + step summary on the failing run
  fail_loud:       "SOLEUR_PR_AFFECTED_RATCHET exit=1 reason=<kind> live=N baseline=M line"

failure_modes:
  - mode:          baseline/accept drift re-reddens every head
    detection:     the ratchet job's own exit marker on the next pull_request run
    alert_route:   the failing check on the PR itself; soak tracker #10865

logs:
  where:           GHA run log for job affected-index-ratchet; --report artifact on RUNNER_TEMP
  retention:       GitHub's run-log retention window

discoverability_test:
  command:         python3 -I scripts/ci-pr-affected-replay.py ratchet
  expected_output: SOLEUR_PR_AFFECTED_RATCHET exit=0
```

## Research Insights

**Premise Validation** (Phase 0.6): every artifact the issue cites is present on the
tree — `scripts/ci-pr-affected-replay.py`, `scripts/ci-pr-affected-audit.accept.tsv`,
`scripts/ci-pr-affected-audit.baseline.tsv` (1510 rows), `scripts/lint-followthrough-varq-ban.sh`,
`scripts/lib/test-affected-paths.sh`, `scripts/lib/trusted-verdict.sh`. Issue #11771 is
OPEN with no merged or open linked PR (collision-precheck: only this run's own draft
PR #11781; two sibling `test-all.sh` runs from `feat-one-shot-11556-epic-ci-time-batch`
are unrelated scope). The measured signature reproduced locally: `exit=1
reason=stale-accept live=1512 baseline=1510`.

**Property List** (Phase 0.6b): (1) the check returns to green on every head; (2) the
repair uses only the ratchet's existing remedies — it must not weaken what the audit
measures (no baseline-row additions, no re-basing); (3) each pair gets the disposition
the runbook's bright-line assigns to it.

**Cut List** (Phase 0.6b): baseline regeneration via `--print-baseline` is prune-only —
it cannot add rows, so it is not a remedy for new pairs, only for dead ones (run at the
end to confirm zero drift). No new scripts, gates, or waivers.

**Live audit reproduction** (this branch, `ratchet --report`):

- `new-pair apps/web-platform/scripts/home-census-trigger.test.sh →
  knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md` — five
  boundary lines (`audit --all-refs`): test-file fixture writes at `:63 :136 :220 :221`
  inside the scratch tree (`REPO="$TMP/repo"`, stub git), plus
  `apps/web-platform/scripts/home-census-trigger.sh:55` — `CLO_RECORD=` fed to
  `git show "${SERVED}:${CLO_RECORD}"` at `:246`, a genuine runtime read.
- `new-pair tests/scripts/betterstack-roundtrip-latency → scripts/lib/trusted-verdict.sh`
  — three echo-diagnostic boundary lines inside `scripts/lint-followthrough-varq-ban.sh`
  at `:318` (`a156176796ef/1`), `:354` (`0e28e1d32b7b/1`), `:599` (`538ede2b0768/1`).
  The first two anchors are already covered by existing accept rows (the lines moved,
  content unchanged); only `538ede2b0768` is uncovered.
- `stale-accept tests/scripts/betterstack-roundtrip-latency →
  scripts/lib/trusted-verdict.sh @ 25a129edb2d6/1` — anchor-not-live; the echo at the
  old `:518` was rewritten (now the `:599` FAILED-summary line, new anchor).

**Dispositions (runbook bright-line applied):**

- home-census pair → **declared edge**. The SUT opens the file's content at runtime
  (`git show`); the rubric's category (b) is met by "a script the suite runs". Edge
  cost: `git log --since=90.days` on the path = 1 commit → ~zero added suite runs.
  Accepting would write a false "mention" claim on a real read — the exact
  false-negative shape the runbook forbids.
- betterstack pair → **anchor-keyed accept row**, same disposition as the pair's two
  existing sibling rows (`message:` kind, echo diagnostic). Verified mention:
  `grep -rn "trusted-verdict\|trusted_verdict" tests/scripts/test-betterstack-roundtrip-latency.sh
  scripts/followthroughs/betterstack-roundtrip-latency-7855.sh` → zero hits; the
  attribution is only through the lint script's echo lines.
- stale row → **correct in place**: update the row's anchor `25a129edb2d6 →
  538ede2b0768` and its cited line `:518 → :599` (same logical diagnostic, amended text).

**Precedent and learnings:**

- PR #11734 (merged 2026-10-31, "accept 7 mention-class boundary lines") — the same
  repair shape for this same job; its fix-round produced
  `learnings/test-failures/2026-10-31-accept-row-reasons-must-enumerate-real-tree-read-arms.md`
  (reason claims must survive every real-tree arm — applied above).
- Runbook `ci-pr-affected-activation.md` §Ratchet red because main moved: repair owner
  is the pair's introducer, fix-forward is "a declare, accept or prune PR that never
  adds a baseline line", due within one working day.
- Not a drain PR: the `s4-drain` claim (`#10448` mirror + label) covers baseline-
  shrinking PRs #10860/#10959/#10861; this repair only declares/accepts/prunes.

**Related issues:** #11771 (this fix), #10959/#10860/#10448/#10865 (S4 siblings —
explicitly out of scope per the issue's own relationship note), #11688 (the PR whose
only red check this repair unblocks).

**External research:** skipped — repo-internal machinery with an authoritative
runbook and a same-week precedent; external material would add nothing.

## Implementation

### Step 1 — Correct the stale accept row and add the uncovered anchor

File: `scripts/ci-pr-affected-audit.accept.tsv`

- Update the row `tests/scripts/betterstack-roundtrip-latency<TAB>scripts/lib/trusted-verdict.sh<TAB>25a129edb2d6<TAB>1<TAB>…:518:…`
  to anchor `538ede2b0768`, citing `scripts/lint-followthrough-varq-ban.sh:599` in the
  reason (same `false-positive: message: <file:line>: an echo diagnostic …` shape as
  the pair's two sibling rows).

### Step 2 — Declare the home-census edge

File: `scripts/lib/test-affected-paths.sh`

- Add, in label-sorted position:

```bash
# apps/web-platform/scripts/home-census-trigger.test.sh — the SUT names the committed
# CLO record (home-census-trigger.sh:55) and opens it via `git show` at :246; the test's
# fixture contract pins the same path, so an edit to the record must still select it.
AFFECTED_APPS_WEB_PLATFORM_SCRIPTS_HOME_CENSUS_TRIGGER_TEST_SH_PATHS=(
  "knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md"
  "apps/web-platform/scripts/home-census-trigger.test.sh"  # self-inclusion
  "scripts/lib/test-affected-paths.sh"                     # THIS FILE
)
```

### Step 3 — Verify the ratchet is green and the baseline needs no prune

- `python3 -I scripts/ci-pr-affected-replay.py ratchet` → expect
  `SOLEUR_PR_AFFECTED_RATCHET exit=0`.
- `python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline > /tmp/pb.tsv
  && diff -q /tmp/pb.tsv scripts/ci-pr-affected-audit.baseline.tsv` — adopt the pruned
  file only if they differ (prune-only; never hand-edit).

## Files to Edit

- `scripts/ci-pr-affected-audit.accept.tsv` — one row corrected (stale anchor → live anchor)
- `scripts/lib/test-affected-paths.sh` — one `AFFECTED_*_PATHS` array added
- `scripts/ci-pr-affected-audit.baseline.tsv` — conditional: only if `--print-baseline`
  output differs (prune-only regeneration)

## Files to Create

- none

## Open Code-Review Overlap

One probe hit: #8800 (census-sandbox write-through hazard in
`scripts/test-all-affected.test.sh`) — matched only because its body names
`scripts/lib/test-affected-paths.sh`. **Acknowledge:** different concern (fixture
builder semantics, not the declaration tables this plan edits); it keeps its own
issue and re-eval date. Not folded in.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Accept rows / edge declarations regenerated against live state — the baseline is oracle-generated" [issue #11771 §Fix] | Steps 1–3 / Files to Edit | mapped |
| 2 | "anchor-keyed accept rows in `scripts/ci-pr-affected-audit.accept.tsv` (mention-class echo diagnostics — same disposition as the existing `betterstack-roundtrip-latency` rows for this suite) or declared edges in `scripts/lib/test-affected-paths.sh` if the reads are real" [issue #11771 §Fix] | Step 1 (accept row for the mention pair) + Step 2 (declared edge for the real-read pair) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| accept-row correction (Step 1) | "anchor-keyed accept rows in `scripts/ci-pr-affected-audit.accept.tsv`" | asked |
| declared edge (Step 2) | "or declared edges in `scripts/lib/test-affected-paths.sh` if the reads are real" | asked — read verified real via `home-census-trigger.sh:246` |
| baseline prune check (Step 3) | "Accept rows / edge declarations regenerated against live state" | inferred — justification: prune-only is the only baseline write the ratchet permits; verifies zero residual drift |

### Split Assessment

- Subsystems touched: 1 — `scripts/` CI-selection machinery
- Planned files: 3 (1 conditional) | Estimated changed lines: ~10
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Domain Review

### Engineering

The only relevant domain: CI-selection machinery owned by the engineering tooling
surface. No product, marketing, legal, finance, sales, support, or operations impact —
the change alters which test suites a diff selects and corrects an audit accept row.
The home-census edge references a legal-audit doc path but makes no legal claim and
changes no legal artifact.

## Enhancement Summary

deepen-plan halt gates verified: User-Brand section present (threshold `none`);
Observability block carries a locally-runnable `discoverability_test` (`python3 -I
scripts/ci-pr-affected-replay.py ratchet`, first token on the allowlist);
PAT-shape grep zero hits; no UI surface; no new data store or connection
(Encryption Posture not required); deliverable introduces no new guard/gate —
Guard Contract halt not triggered; `## Scope Check` present with both asks
mapped and one justified `inferred` row.

### New Considerations Discovered

- The home-census pair's fifth boundary line lives in the SUT source
  (`home-census-trigger.sh:55`), not the test file — `audit --all-refs` (not the
  3-capped ratchet report) was required to see it; it is what flips the pair
  from mention to real-read (CTO ruling R1).
- Two sibling accept rows' reason texts cited moved line numbers
  (`:311`/`:347` vs live `:318`/`:354`) — corrected in the same edit per the
  CTO's cosmetic-honesty note.

## Acceptance Criteria

- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet` prints
  `SOLEUR_PR_AFFECTED_RATCHET exit=0` on this branch.
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline` output
  equals `scripts/ci-pr-affected-audit.baseline.tsv` (or the file is replaced by the
  pruned output — never hand-edited).
- [ ] No accept row in `scripts/ci-pr-affected-audit.accept.tsv` is stale
  (`anchor-not-live`): `ratchet` reports zero `stale-accept` rows.
- [ ] The new `AFFECTED_*_PATHS` array passes the census linter
  (`scripts/lint-orphan-test-suites.sh` clean on the label).
- [ ] `Closes #11771` on the PR body.
