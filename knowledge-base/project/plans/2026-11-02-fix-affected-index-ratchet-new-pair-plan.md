---
title: "fix(ci): repair affected-index-ratchet — declare plugins/soleur edge for inngest-userdata-budget.sh"
type: fix
date: 2026-11-02
slug: fix-affected-index-ratchet-new-pair
branch: feat-one-shot-11848-ratchet-accept-row
issue: 11848
closes: 11848
lane: cross-domain
brand_survival_threshold: none
---

# fix(ci): repair affected-index-ratchet — declare plugins/soleur edge for inngest-userdata-budget.sh

Spec lacks valid `lane:` (no spec.md exists for this one-shot branch) — defaulted to cross-domain (TR2 fail-closed).

## Overview

`affected-index-ratchet` (advisory, S4 PR3a, ADR-276 amendment) is red on main merge_group runs:
`SOLEUR_PR_AFFECTED_RATCHET exit=1 reason=new-pair live=1511 baseline=1510` — one live
`(suite, path)` pair over the committed baseline. The red pauses the #10865 observation-window
probe (`the latest merge_group unit is red: repair main first`), which stalls the S4 PR3a soak leg
of epic #11556. The repair is one line in `scripts/lib/test-affected-paths.sh`: declare
`apps/web-platform/infra/inngest-userdata-budget.sh` in `AFFECTED_PLUGINS_SOLEUR_PATHS`.

This plan **diverges from issue #11848's prescribed fix** (an anchor-keyed accept row) on verified
evidence — see `## Research Reconciliation` and `knowledge-base/project/specs/feat-one-shot-11848-ratchet-accept-row/decision-challenges.md`
(the `pending - assumed` technical ruling; no agent-spawn tool exists on this harness, so the CTO
consult is recorded rather than executed). The issue's `Closes #11848` / `Ref #10865` / `Ref #11556`
PR-body requirements are unchanged and restated in the Acceptance Criteria.

## Problem Statement / Motivation

Merge_group run 41408788451 (2026-11-02T07:49Z), verified from the job log:

```text
new-pair  plugins/soleur  apps/web-platform/infra/inngest-userdata-budget.sh  plugins/soleur/test/terraform-target-parity.test.ts:5876
  cause: your change touched neither plugins/soleur/test/terraform-target-parity.test.ts nor apps/web-platform/infra/inngest-userdata-budget.sh (main is already red for this pair, or a covering edge was removed): rebase, then declare the edge or add an accept row
  ref  plugins/soleur/test/terraform-target-parity.test.ts:5876  ef13fc106737/1  const RUN_FULL = " run: bash apps/web-platform/infra/inngest-userdata-budget.sh --cap-only\x5cn";
SOLEUR_PR_AFFECTED_RATCHET exit=1 reason=new-pair live=1511 baseline=1510
```

Introduced by merged PR #11815 (`b9deac6de5`, "feat(infra): split the Inngest host Doppler token
into a read boot token and a read/write flip token"), which added the literal
`run: bash apps/web-platform/infra/inngest-userdata-budget.sh --cap-only` string inside a
yaml-content assertion in `terraform-target-parity.test.ts:5876`.

Reproduced locally on this worktree (unmodified main tree, ~4 min):
`PR_AFFECTED_REPLAY_SELECT_TIMEOUT=290 python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main`
→ identical `exit=1 reason=new-pair live=1511 baseline=1510` with the same `ref` line.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
|---|---|---|
| "The suite reads the workflow file, never the script — naming-only edge, false-positive accept class" | True of `terraform-target-parity.test.ts` (the boundary line) but **false of the `plugins/soleur` suite**: `plugins/soleur/test/cloud-init-user-data-size.test.ts` opens the real script (`readFileSync(BUDGET_SH)`, line ~2219) and executes it (`spawnSync("bash", [BUDGET_SH, ...args])`, line ~2223) via `BUDGET_SH = join(INFRA, "inngest-userdata-budget.sh")` where `INFRA = join(REPO_ROOT, "apps", "web-platform", "infra")`. The read is invisible to the audit's literal-name scan ("literal names only: no computed path" — `ci-pr-affected-replay.py` DECLARED LIMITS). Deleting or changing the script breaks this suite — a real dependency, not a mention. | Prescribe the **declare** remedy, not the accept row. |
| "a declared edge would run the full battery on every script touch" | A declared edge selects the `plugins/soleur` suite (`bun test plugins/soleur/`, `scripts/test-all.sh:7103`) only. The full-battery cost is paid once — on THIS PR — because editing `scripts/lib/test-affected-paths.sh` is itself a runner trigger (`AFFECTED_FALLBACK reason=runner-changed`). | Corrected in Proposed Solution. |

The runbook prescribes the disposition check the issue skipped
(`ci-pr-affected-activation.md` §Ratchet red, remedy 2): "Before accepting any pair, grep the
declared file for the path's basename and its parent directory as separate string literals: an
audit boundary line is the literal path, and a computed construction (`os.path.join`, a
`$ROOT/...` concatenation) reads the file without producing one." Running that grep
(`grep -rn "inngest-userdata-budget" plugins/soleur/`) found `join(INFRA, "inngest-userdata-budget.sh")`
plus `readFileSync`/`spawnSync` — the pair is a **real read**, and "an accept row on a file the
suite really reads is a false negative that becomes live once the lever flips" (the lever = PR3b
#10859 making the context required).

## Proposed Solution

Declare the edge — exactly what the selector needs to know: a diff touching
`apps/web-platform/infra/inngest-userdata-budget.sh` selects the `plugins/soleur` suite.

In `scripts/lib/test-affected-paths.sh`, inside `AFFECTED_PLUGINS_SOLEUR_PATHS` (starts ~line 935),
insert after `"apps/web-platform/infra/inngest-server-flip-guard.sh"` (line ~960) and before
`"apps/web-platform/infra/inngest-wiped-volume-verify.sh"` (line ~961), keeping the array's
sorted order and its issue-cited comment convention:

```bash
  # #11848: cloud-init-user-data-size.test.ts reads and executes the real script via BUDGET_SH (join(INFRA, ...)); terraform-target-parity.test.ts only names it in a yaml-pin.
  "apps/web-platform/infra/inngest-userdata-budget.sh"
```

(Comment cites the `BUDGET_SH` symbol anchor, not a bare line number, per the constitution's
symbol-anchor rule.)

Expected ratchet effect: the pair is credited by `edge_hit`, live drops 1511 → 1510 = baseline →
green. The `oracle-inputs-changed: scripts/lib/test-affected-paths.sh` warning will print
non-blocking (the edge file is an oracle input); that is expected and announced, not a verdict.

**Drain-reveal risk: assessed zero, re-verified at work time.** Declaring a code file makes the
audit read it and surface every tracked path it literally names as new pairs. The script's
non-comment lines contain no literal repo-relative path (every file reference is `$DIR`-computed
or inside a comment; comments are stripped) — verified by
`grep -vE '^\s*#' apps/web-platform/infra/inngest-userdata-budget.sh | grep -nE 'apps/|plugins/|scripts/|knowledge-base/|\.github/'`
→ zero hits. The work phase re-runs `ratchet --report` after the edit anyway; any revealed pair
is handled by the runbook fixpoint (declare real reads, accept mentions) in the same PR.

**The accept-row arm is documented-and-rejected** (recorded for review completeness): the row
`plugins/soleur<TAB>apps/web-platform/infra/inngest-userdata-budget.sh<TAB>ef13fc106737<TAB>1<TAB>false-positive: …`
would silence the red but certifies "suite merely names the file" — refuted by the `BUDGET_SH`
read/execute. If a binding ruling prefers accept on cost grounds, the row belongs in C-locale
order immediately before line 97 of `scripts/ci-pr-affected-audit.accept.tsv` (first
`plugins/soleur<TAB>` row) and its reason must record that the suite DOES read the file via a
computed path — i.e., it would be a knowingly-certified false negative needing a tracking issue.

## Files to Edit

- `scripts/lib/test-affected-paths.sh` — add one edge line + one comment line to
  `AFFECTED_PLUGINS_SOLEUR_PATHS` (~line 960).

## Files to Create

None. (Pipeline artifacts — this plan, `tasks.md`, `decision-challenges.md`,
`session-state.md`, `knowledge-base/INDEX.md` regeneration — are knowledge-base bookkeeping, not
deliverables.)

## Implementation Phases

Single phase. This is `Fix-Size: XS`.

1. Insert the edge line + comment in `AFFECTED_PLUGINS_SOLEUR_PATHS` at the sorted position
   (between `inngest-server-flip-guard.sh` and `inngest-wiped-volume-verify.sh`).
2. Verify: selector shows `plugins/soleur` selected on a diff touching the script; ratchet exits
   0 locally; full local gate runs (runner-triggered fallback expected — note it in the PR).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — a CI signal artifact. If the
  declare were wrong (e.g., the edge file malformed), the affected-index ratchet and/or the
  required `test` gate stays red, blocking merges — an operator-visible CI outage, not a user one.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — a one-line path
  string in an edge declaration; no secrets, data, or user state touched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** CI-internal tooling repair; no user-facing surface,
  no sensitive-path match under the canonical `SENSITIVE_PATH_RE` (`scripts/lib/` is not
  `apps/*/infra/`, not Doppler/workflow-scoped).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "repair affected-index-ratchet red on main" [issue #11848 title] | Files-to-Edit entry `scripts/lib/test-affected-paths.sh` | mapped |
| 2 | "Add one anchor-keyed accept row to `scripts/ci-pr-affected-audit.accept.tsv`" [issue #11848 §Fix] | — | descoped — justification: the issue's premise is refuted; the suite really reads+executes the script (`BUDGET_SH` read/execute in cloud-init-user-data-size.test.ts), so the runbook-correct remedy is the declared edge; recorded as a `pending - assumed` technical ruling in decision-challenges.md |
| 3 | "The PR must `Closes #11848` on its own body line, and `Ref #10865`/`Ref #11556` elsewhere" [brief] | AC-5 | mapped |
| 4 | "reproduce the new-pair finding locally … confirm accept-tsv row ordering/format conventions" [brief] | Research Insights + AC-3 (reproduced at plan time; ordering documented) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `scripts/lib/test-affected-paths.sh` (declare edge) | "rebase, then declare the edge or add an accept row" (ratchet cause text quoted in issue) — issue asks for repair; the two-runbook-remedy fork resolves to declare on verified evidence | inferred — justification: the pair's real-read disposition per `ci-pr-affected-activation.md` §Ratchet red |
| AC-5 PR-body linkage | "Closes #11848 on its own body line, and `Ref #10865`/`Ref #11556` elsewhere in the body" [brief] | asked |
| Local-replay verification AC | "reproduce the new-pair finding locally if a cheap replay exists" [brief] | asked |

### Split Assessment

- Subsystems touched: 1 — `scripts/`
- Planned files: 1 | Estimated changed lines: 2
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC-1. `AFFECTED_PLUGINS_SOLEUR_PATHS` in `scripts/lib/test-affected-paths.sh` contains the
      literal line `"apps/web-platform/infra/inngest-userdata-budget.sh"` exactly once, positioned
      between the `inngest-server-flip-guard.sh` and `inngest-wiped-volume-verify.sh` entries, with
      a comment citing `#11848` and the `BUDGET_SH` anchor (verify:
      `grep -n "inngest-userdata-budget" scripts/lib/test-affected-paths.sh`).
- [ ] AC-2. `bash scripts/test-all.sh --print-selection --paths=apps/web-platform/infra/inngest-userdata-budget.sh`
      prints an `AFFECTED_SELECTED\tplugins/soleur\t1\t` row (selected=1).
- [ ] AC-3. `PR_AFFECTED_REPLAY_SELECT_TIMEOUT=290 python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main`
      prints `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass` with `live=<n> baseline=<n>` where the
      two counts are EQUAL (plan-time expectation `live=1510 baseline=1510`; if main moved, the
      equality — not the literals — is the criterion). If `--report` shows any NEW revealed pair
      from reading the script, it is handled per the runbook fixpoint before this AC is claimed,
      and the deviation is logged.
- [ ] AC-4. The diff adds no row to `scripts/ci-pr-affected-audit.accept.tsv` and does not touch
      `scripts/ci-pr-affected-audit.baseline.tsv` (source-file diff scope: only
      `scripts/lib/test-affected-paths.sh`, plus the knowledge-base artifacts this pipeline writes —
      plan, tasks.md, decision-challenges.md, session-state.md, INDEX.md).
- [ ] AC-5. The PR body contains the line `Closes #11848` on its own line, plus `Ref #10865`,
      `Ref #11556`, and `Ref #11771` elsewhere — never `Closes`/`Fixes` for the Ref'd issues.
- [ ] AC-6. The `affected-index-ratchet` job on this PR's merge_group run reports green (the job is
      advisory but the run concludes and the `SOLEUR_PR_AFFECTED_RATCHET` marker is `exit=0`).

## Test Scenarios

- **Reproduce (done at plan time, recorded):** ratchet on unmodified tree → `exit=1 reason=new-pair live=1511 baseline=1510`. Command in AC-3.
- **Happy path:** after the edge line, selector credits `edge:declared` for the pair; ratchet exits 0.
- **Negative control:** with the edge line removed, AC-2 reports `plugins/soleur\t0\t` — the AC
  distinguishes the fix's presence from absence (not a tautology).
- **Reveal control:** post-edit `python3 -I scripts/ci-pr-affected-replay.py ratchet --report /tmp/ratchet.full --base origin/main`
  → `--report` file contains no `new-pair` lines naming paths OTHER than the repaired one.
- **Guard:** `bash scripts/test-affected-kb-consumers.test.sh` stays green (the edge file's own
  census suites — kb-consumers unaffected, but the runner-triggered fallback runs the whole local
  battery anyway; note `AFFECTED_FALLBACK reason=runner-changed` is EXPECTED on this PR).

## Success Metrics

- `affected-index-ratchet` green on main merge_group runs after merge → #10865
  observation-window probe un-pauses (`ratchet-observation-window-10865.sh` stop condition clears).
- Zero pairs added to `ci-pr-affected-audit.baseline.tsv` or `ci-pr-affected-audit.accept.tsv`.

## Dependencies & Risks

- **Hot-file cost:** `inngest-userdata-budget.sh` has 12 commits/90 days — each script-touch PR
  selects the `plugins/soleur` bun suite. That is the correct consequence of a real dependency
  (the suite asserts the script's stub widths, entropy labels, floor semantics, `--cap-only`
  behavior), not an argument to falsify the index. Cost recorded in the ruling row.
- **Ruling risk:** the declare-vs-accept disposition is `pending - assumed` (no CTO spawn on this
  harness). If review overturns to accept, the rejected arm in Proposed Solution has the exact row
  and insertion point — but that arm certifies a false negative and MUST carry a tracking issue.
- **Ordinal drift:** accept-file format verified (`load_accept` at
  `ci-pr-affected-replay.py:1485`): 5 TSV columns, C-locale sorted convention, `false-positive: `
  reason prefix, anchor = first-12-hex sha256 of `" ".join(line.split())` of the comment-stripped
  line (verified: line 5876 hashes to `ef13fc106737`), ordinal = Nth identical line in canonical
  read order (`ef13fc106737/1` confirmed by the `ref` line).
- **One-day SLA:** the runbook makes repair due within one working day; the introducing author
  owns it, #10448's owner is fallback. This pipeline is that repair.

## References & Research

### Research Insights

**Premise validation (Phase 0.6):** #11848 OPEN (unblocked, no closing PRs — PR #11850 is this
pipeline's own draft on this branch, not a foreign collision); #10865 OPEN soak tracker (Ref-only);
#11556 OPEN epic (Ref-only); PR #11815 MERGED 2026-11-02T03:57Z (`b9deac6de5`). Cited files all
exist on `origin/main`; merge_group run 41408788451 log confirms the exact `new-pair`/`ref`/`exit=1`
lines. Collision pre-check `SOLEUR_COLLISION exit=10 prs=11850` resolved: own pipeline PR.
Premise holds, except the §Fix prescription — reconciled above.

**Property list (Phase 0.6b):** (a) `affected-index-ratchet` green on main merge_group → un-pause
the #10865 probe. (b) The index's selection model stays honest — a suite that really reads a file
is selected when the file changes.

**Cut list (Phase 0.6b):** baseline-row edit — no mechanism exists (`--print-baseline` is
prune-only, growth rule refuses additions; runbook: "a baseline row cannot be added"). Accept row —
covers property (a) but violates (b): certifies a false negative over a real read. Weakening the
terraform-target-parity pin or moving the literal out of the test — destroys a deliberate
mutation-battery assertion to satisfy the audit; backwards.

**Relevant file paths:**
- `scripts/lib/test-affected-paths.sh:935` — `AFFECTED_PLUGINS_SOLEUR_PATHS` (insertion ~line 960).
- `plugins/soleur/test/cloud-init-user-data-size.test.ts:2217-2226` — `BUDGET_SH` real read+execute.
- `plugins/soleur/test/terraform-target-parity.test.ts:5876` — the boundary line (yaml-string pin).
- `scripts/ci-pr-affected-replay.py:121-162` — accept-file format + ratchet semantics.
- `scripts/ci-pr-affected-audit.accept.tsv` — C-locale sorted, 5-col TSV (not edited).
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §Ratchet red —
  the two-remedy decision rule + computed-path pre-acceptance grep.
- `.github/workflows/ci.yml:417-468` — advisory job; `python3 -I … ratchet` invocation copied by AC-3.

**Institutional learnings:**
- `knowledge-base/project/learnings/test-failures/2026-11-01-ratchet-repair-pair-disposition-moved-echoes-and-sut-source-boundary.md`
  — "one real-read boundary line makes the whole pair a declared edge, even when every other line
  is a fixture mention"; "ambiguity resolves to the stricter default" (prior CTO ruling, #11771 →
  PR #11781 — same repair class, did BOTH a row correction AND a home-census edge declare).
- `knowledge-base/project/brainstorms/2026-10-12-ci-path-aware-gating-brainstorm.md` — S4 context.

**Related issues/PRs:** #11848 (target), #10865 (probe it un-pauses), #11556 (epic), #11815
(introducing PR), #11771 → PR #11781 (identical repair-class precedent), #10859 (PR3b — the lever
that makes a false-negative accept row live), #10448 (ratchet introduction).

**CLAUDE.md conventions applied:** kebab-case artifacts; plan filename format; symbol-anchor
comments (no bare line numbers in code comments); no `version` keys; PR body `Closes`/`Ref` rules.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies contain no reference to
`scripts/lib/test-affected-paths.sh` or this pair (checked 2026-11-02).
