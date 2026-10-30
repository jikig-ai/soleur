---
title: "chore(registry): close #10932 residuals 2 and 3 in the W9 restore-step guard"
date: 2026-10-30
slug: registry-restore-w9-residuals-2-3
branch: feat-one-shot-10932-residuals-2-3-restore-w9
issue: 10932
type: chore
closes: none
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# chore(registry): close #10932 residuals 2 and 3 in the W9 restore-step guard

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

Residuals 2 and 3 of #10932 (umbrella #9757) in one PR (draft PR #11589; the operator overrode the earlier
one-residual-per-PR rule; residual 1, the runbook sentence, merged 2026-10-29 as #11557). Every deliverable is
in one file, `tests/scripts/test-registry-d10-workflow-wiring.sh` ("the wiring suite", W9 block). Nothing else
is edited:

- **Residual 2 (wording).** Two stale texts in the W9 block, re-counted against the live engine header (it lists
  seven failure codes: 1, 2, 3, 4, 5, 6, 78).
- **Residual 3a.** The apply workflow's "Restore summary" step has no test at all. Add a test-only check, no
  workflow edit.
- **Residual 3b.** A `die` whose code is computed is invisible to the header-vs-emitted-codes check. Add a
  word census in the suite that goes red on any `die`/`exit` word that is not a literal-code site or one of two
  allowed `die()` lines. Engine and lib untouched.
- **Residual 3c.** A swap of the W9 verdict (`if true`) is not caught by W9's own controls. Add an end-to-end
  meta-control (nested run of the suite on a `drop1`-mutated tree) for the real W9 row and a same-path canary for
  the verdict function used by the controls loop.

No edit to `.github/workflows/apply-web-platform-infra.yml`, `scripts/registry-restore-from-ghcr.sh`,
`tests/scripts/lib/restore-engine-header.sh`, `tests/scripts/test-registry-pull-path-health.sh` or any other
path in `REGISTRY_BATTERY_PATHS`. So: no production apply is fired by this PR, the 869-byte workflow headroom
is not touched, and the ~860 s registry mutation battery is not armed. The byte-budget and #11551 conflict
risks below are therefore CONTINGENT (they bite only if a later ruling reopens a workflow edit).

## Research Insights

### Premise Validation (Phase 0.6)

Checked on 2026-10-30 against `origin/main` (e9d8951780):

- #10932 OPEN, #9757 OPEN. Residual 1 landed: PR #11557 MERGED 2026-10-29 ("runbook states the engine header table
  lists exit 1"); `git grep 'tracked on #10932' origin/main -- knowledge-base/engineering` prints nothing.
  The earlier items (b) `1)` arm, (c) runbook row, (d) header-derived enumeration: PR #11438 MERGED. Engine header
  row for exit 1: on main (the header lists 1, 2, 3, 4, 5, 6, 78).
- Collision pre-check (`collision-precheck.sh`): the only open change naming #10932 is this PR (#11589). It
  reports seven foreign `test-all.sh` processes (other worktrees), i.e. the local test queue is busy. The
  plan's gates assume the local battery may queue (rc 6): CI's required `test` context is then the authority.
- PR #11551 (branch `feat-one-shot-11294-redact-random-id-logs`) is OPEN, ready, and already reports
  `CONFLICTING / DIRTY` against main; it edits `.github/workflows/apply-web-platform-infra.yml` among 18 files.
  This plan does not edit that file, so no textual conflict arises from this PR.
- Staleness of each sub-item on current origin/main (`git grep`/read, not memory):
  - Residual 2 comment: `tests/scripts/test-registry-d10-workflow-wiring.sh:348` still says "(the header does not
    list it)". STALE (real).
  - Residual 2 message: line 495 says "fewer than 6 failure codes" while the guard is `-ge 7` and the header
    lists 7 codes. STALE (real).
  - 3a: `git grep -i 'restore summary\|RESTORE_RESULT' origin/main -- tests` finds only the comment in the wiring
    suite saying the step is not covered. REAL.
  - 3b: the engine has no computed site today (only the `die()` definition and its `exit "$code"`); the
    invisibility is latent, not a live bug. REAL as a latent gap; closed by a census.
  - 3c: REAL (the row and the loop verdicts are never exercised on a failing input).
  - Dropped sub-items: none. Noted as already done by earlier PRs and therefore NOT re-planned: the stale
    "#10932 tracks the workflow arm" comments in the lib and in `test-registry-pull-path-health.sh` (gone from
    both on main), credential-env pin, job-level key pin, shell-code wording (126/127/137/143).

### Property List and Cut List (Phase 0.6b)

Properties (observable outcomes):

1. P1: The two stale W9 texts describe the header as it is today (7 codes, header lists exit 1).
2. P2: The "Restore summary" step cannot silently stop running on failure, change its trigger/input, or print the
   wrong outcome text, without a PR check turning red.
3. P3: A `die`/`exit` in the restore engine whose code is not a literal turns a PR check red instead of being
   invisible to the header-vs-emitted-codes comparison.
4. P4: Turning the W9 row verdict, or the verdict function the controls loop uses, into an unconditional pass
   turns a PR check red (a hardcode at the loop's call site is accepted residue).

Mechanisms proposed by the brief and what already covers them: (a) a workflow edit to the summary step — the
property needs only a test; (b) an engine edit so `die` sites are lintable — the property needs only a test-side
census (CTO F2); (c) a new suite file — the wiring suite already owns W9 and its sources.

Cut List:

| Mechanism | Property | What already covers it / why cut |
|---|---|---|
| Workflow edit fixing the summary's "The step above emitted one ::error::" wording | none of P1-P4 | cosmetic; edit fires the production apply and conflicts with #11551 (CTO F1b). Accepted residue |
| Engine edit to make `die` sites lintable | P3 | the census in the suite covers P3 with the engine byte-identical (CTO F2b) |
| Edit to `restore-engine-header.sh` to add the census | P3 | lib is a battery path (arms ~860 s); the suite hosts it instead |
| Command-position grammar and census-vs-extractor cross-check (original draft) | P3 | cut at plan review (CTO S2). The mutation the cross-check killed was "a computed die at a call position the grammar's anchor set misses"; the word census has no anchor set, and Guard 2 sandbox rows 7 and 9 (`die 3 "x" \|\| exit "$c"`, `builtin exit "$c"`, `trap 'exit "$c"' ERR`) prove a surviving assertion kills it |
| `sumkeys`/pairwise-differ/`failure`-value controls, must-pass nested tree (original draft) | P2, P4 | cut at plan review (CTO S1/S3): each is covered by a pin, an anchor or the outer real row |
| Dropping the `grep -vx 1` ignore | none | outside the brief; separate follow-up (CTO F5) |
| New standalone test file | P2-P4 | the wiring suite already has the helpers (`W9_PY`, `w9_run`, controls) |

### Applicable learnings

- `2026-10-23-a-guard-over-a-case-statement-should-run-the-case-not-parse-it.md` — run the real body with
  stubs; controls mutate the real artifact, assert the mutation landed and the refusal names the right cause.
  Drives 3a (run the summary body) and 3b (the census is a text check, so it is a word census with no anchor
  set to under-enumerate, and its residue is named).
- `2026-10-28-my-new-runbook-sentence-...-a-job-key-allowlist-left-twenty-edits-green.md` — pin a mapping
  exactly or not at all; give each pin a control whose expected fragment only that pin produces; split messages
  so two controls cannot be satisfied by one line. Drives the 3a pin set and message design.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — a matrix mutating only
  the system under test cannot see a vacuous harness; need harness rows and non-canonical must-PASS inputs.
  Drives 3c and the must-PASS rows.
- `2026-10-22-a-verdict-function-inside-command-substitution-cannot-exit-...md` — a verdict function used in
  `$( )` cannot exit; return the verdict as data. Drives `w9_expect` (prints `ok`/`fail`) for the controls loop.
- `2026-10-20-a-census-guard-under-counts-on-both-enumerators.md` — a census under-counts when its enumerator
  has an anchor set. Drives the choice of a word census over a call-position grammar (a first prototype anchor
  set missed the case-arm `)` position).
- `2026-10-29-a-plan-ac-count-i-saw-disagree-was-left-for-review-to-find.md` — when a literal AC command prints a
  different number than the plan states, fix the AC in the same step.

### Evidence collected at plan time

- Suite baseline: 47 passed / 0 failed in 52 s (one run on this tree). One `w9_check` is ~2 s; 25 calls
  (1 real, 23 controls, 1 extra-code) dominate.
- Engine word census (comment-blanked text, the two allowed `die()` lines removed, token pass
  `grep -noE '\b(die|exit)\b( [0-9]+\b)?'`): 82 tokens, all of the literal `die N`/`exit N` shape, 0 offenders.
  The lib extractor's pattern finds the same 82 literal sites. A command-position grammar (the first draft) needed
  `)` as an anchor to reach 83 = 82 + 1 and was cut for that fragility.
- Summary step (workflow job `registry_store_restore`, last step): `if: always()`, env
  `RESTORE_RESULT: ${{ job.status }}`, body writes only to `$GITHUB_STEP_SUMMARY`. Run under `env -i` with
  values `success`, `cancelled`, `failure`, `skipped`, empty: stdout empty; success -> "closed"; cancelled ->
  "cancelled"; failure/skipped/empty -> "failed" (the `*)` arm). `W9_PY`'s `extract`/`env` modes work for this
  step; its `keys` mode forbids `if` and so cannot be reused.
- `tests/scripts/test-registry-d10-workflow-wiring.sh` is NOT in `REGISTRY_BATTERY_PATHS`
  (`scripts/lib/test-relevance-paths.sh`); `tests/scripts/lib/restore-engine-header.sh` is. The workflow is the
  only apply trigger; `tests/` files are not in its `paths:`.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| Residual 2: the comment near line 348 says the header does not list exit 1 | True on main: line 348 reads "(the header does not list it)"; the header lists 1 | Reword (Phase 4) |
| Residual 2: message near line 495 says "fewer than 6" while the guard is `-ge 7` | True: line 495; header yields 7 codes (1,2,3,4,5,6,78); `tested` = {1} union header = 7 | "fewer than 7"; keep `-ge 7` |
| 3a: "Restore summary" step is a residual | Uncovered by any test; the step is not engine-coupled | Test-only closure, no workflow edit |
| 3b: "reads only literal `die N` / `exit N`" | True; engine has zero computed sites today (latent) | Census tripwire in the suite |
| 3c: "the W9 verdict swap" | The 2026-10-28 comment's claim that the assertion-count floor backs it is false (`_report` counts any `ok`) | Hybrid meta-control plus canary |
| Brief: "Prefer solving computed `die` visibility in the test lib" | The lib is a battery path; editing it arms ~860 s | Solve in the suite (CTO F2/F2b), brief's fallback "test-side check" |
| Brief: the workflow "fires the production apply" if edited | Only if edited; this plan does not edit it | Stated as contingent |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the comment near line 348 \"Exit 1 is added to the tested population (the header does not list it)\" is stale" [brief] | Phase 4 task 4.1 | mapped |
| 2 | "the W9 fail message near line 495 says \"fewer than 6 failure codes\" while the guard is `-ge 7`" [brief] | Phase 4 task 4.2 | mapped |
| 3 | "(a) the apply workflow's \"Restore summary\" step" [brief] | Phase 2 (Guard 1) | mapped |
| 4 | "(b) computed `die \"$x\"` sites" [brief] | Phase 1 (Guard 2) | mapped |
| 5 | "(c) the W9 verdict swap in tests/scripts/test-registry-d10-workflow-wiring.sh" [brief] | Phase 3 (Guard 3) | mapped |
| 6 | "drop any sub-item that is no longer real and say so in the plan and PR body" [brief] | Premise Validation + Residual Classification; PR-body task 5.4 | mapped (none dropped) |
| 7 | "Any edit to it must be size-neutral or shrinking" / "flag the byte-budget and textual-conflict risk in the plan, and have work re-measure the byte count after rebasing" [brief] | Byte-budget section; Phase 0 task 0.4; AC | mapped |
| 8 | "Prefer solving computed `die \"$x\"` visibility in the test lib or by a test-side check; touch the engine script only if a technical ruling" [brief] | decision-challenges F2/F2b (engine not necessary) | mapped |
| 9 | "Mutation-prove any new or changed assertion on a sandbox copy (allocate with scripts/soleur-sandbox.sh), restoring from a pristine copy, never git checkout." [brief] | Phase 5 task 5.2 | mapped |
| 10 | "Record every technical fork as a decision-challenges.md row ruled by `soleur:engineering:cto`" [brief] | `specs/<branch>/decision-challenges.md` (done at plan time) | mapped |
| 11 | "if this clears every remaining residual, say so plainly and ask before closing #10932" [brief] | Phase 5 task 5.4 (it does NOT clear them all; two remain) | mapped |
| 12 | "Reuse the learnings under knowledge-base/project/learnings/ about guard vacuity and mutation batteries" [brief] | Research Insights, Guard Contract | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Files to Edit: `tests/scripts/test-registry-d10-workflow-wiring.sh` | "(c) the W9 verdict swap in tests/scripts/test-registry-d10-workflow-wiring.sh" | asked |
| Phase 1 census `w9_computed_sites` | "(b) computed `die \"$x\"` sites" | asked |
| Phase 2 `w9_summary_check` and its W9_PY modes/controls | "(a) the apply workflow's \"Restore summary\" step" | asked |
| Phase 3 nested meta-control (`W9_NESTED=1`, sentinel 64) | "(c) the W9 verdict swap" | asked |
| Phase 3 `w9_expect` canary for the controls loop | "(c) the W9 verdict swap" | asked |
| Phase 4 wording edits | "the comment near line 348" / "the W9 fail message near line 495" | asked |
| Phase 4 header-block rewrite ("NOT covered here", "A text parse of the case ...") | — | inferred — justification: both sentences become false once 3a/3b land (CTO F4); leaving them is a new stale comment, the exact defect residual 2 fixes |
| Phase 4 `EXPECTED_ASSERTIONS` recount | "the wiring suite count changes if assertions are added" | asked |
| decision-challenges.md, tasks.md | "Record every technical fork as a decision-challenges.md row" | asked |
| Byte-budget section and Phase 0 re-measure | "have work re-measure the byte count after rebasing" | asked |

### Split Assessment

- Subsystems touched: 1 — `tests/scripts/` (plus planning artifacts under `knowledge-base/project/`)
- Planned files: 1 code file (+ 4 planning artifacts) | Estimated changed lines: ~150 added, ~12 modified
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (the operator asked for one PR; no threshold is near)

## Residual Classification (the #10932 comments of 2026-10-23, 2026-10-28, 2026-10-29)

| Item | Meaning (pinned from the code and the earlier plans) | Still stale on origin/main? | Disposition |
|---|---|---|---|
| R2a comment | wiring suite comment "Exit 1 is added to the tested population (the header does not list it)" | Yes | Fix (Phase 4) |
| R2b message | `w9_add "... fewer than 6 failure codes (header reshaped?)"` beside the `-ge 7` guard | Yes | Fix (Phase 4) |
| R3a | W9 has no coverage of the job's last step "Restore summary" (`if: always()`, `RESTORE_RESULT: ${{ job.status }}`, a `case` printing a per-outcome markdown block to `$GITHUB_STEP_SUMMARY`) | Yes | Test-only check (Phase 2) |
| R3b | `restore_emit_codes` reads literal `die N` / `exit N` only; a `die "$x"` is invisible to the W9 header-vs-emit comparison | Latent (engine has none) | Census tripwire in the suite (Phase 1) |
| R3c | verdict swap: the W9 row (`if [[ -z "$w9_problems" ]]; then ok else fail`) and each control's `if grep -qF ... ok else fail` are never run on a failing input, so `if true` leaves the suite green | Yes | Meta-control + canary (Phase 3) |
| Already done, not re-planned | credential env pin, job-level key pin, shell codes 126/127/137/143 wording, stale "#10932" comments in the lib and the pull-path-health suite | Done by #11438 and the follow-on PRs of 2026-10-29 | Nothing |
| Stays open after this PR | (i) the `grep -vx 1` ignore on both sides of the header-vs-emit comparison (a deleted header row for 1 stays green); (ii) engine-owned wording ("Nothing was copied", arm 3 "The store is EMPTY") | Yes | NOT in the brief; left open (CTO F5). #10932 is therefore NOT cleared |

## Files to Edit

- `tests/scripts/test-registry-d10-workflow-wiring.sh` — the only code change: new `W9_PY` modes (`sumextract`,
  `sumenv`, `sumkeys`, `mutate:sum*`), `w9_computed_sites`, the census call inside `w9_check`,
  `w9_summary_check` and its controls, `w9_expect`, the `W9_NESTED` guard and the meta-controls, the wording
  fixes, `EXPECTED_ASSERTIONS`.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-10932-residuals-2-3-restore-w9/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-10932-residuals-2-3-restore-w9/decision-challenges.md` (written)
- (pipeline) `knowledge-base/project/specs/feat-one-shot-10932-residuals-2-3-restore-w9/session-state.md`

## Files NOT touched (asserted by AC)

`.github/workflows/apply-web-platform-infra.yml`, `scripts/registry-restore-from-ghcr.sh`,
`tests/scripts/lib/restore-engine-header.sh`, `tests/scripts/test-registry-pull-path-health.sh`,
`tests/scripts/test-registry-restore-from-ghcr.sh`, `scripts/lib/test-relevance-paths.sh`,
`scripts/lib/test-affected-paths.sh` (a `PR_GATE_MACHINERY` member: editing it arms every battery), the rationale
doc, the runbooks, `scripts/test-all.sh`, `scripts/suite-*.tsv`.

## Open Code-Review Overlap

None. (`code-review` issues queried; no body names `tests/scripts/test-registry-d10-workflow-wiring.sh`,
`tests/scripts/lib/restore-engine-header.sh`, `scripts/registry-restore-from-ghcr.sh` or the apply workflow.)

## Byte-budget and #11551 conflict risk (contingent; flagged per the brief)

This plan does not edit the workflow, so neither risk materialises. They are recorded because a later ruling or a
review finding could reopen a workflow edit (for example the loose "The step above emitted one ::error::"
summary wording, ruled out by CTO F1b):

- Byte budget: `wc -c .github/workflows/apply-web-platform-infra.yml` printed 489,131 against the 490,000 gate
  (`plugins/soleur/test/workflow-file-size.test.ts`), 869 bytes of headroom. Any workflow edit must be
  size-neutral or shrinking, with prose moved to
  `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`.
- Apply firing: any edit to the workflow is a push-path trigger of the production apply (`infra-privileged`);
  the PR would ride that apply and must say so in its body.
- #11551 also edits the workflow and is `CONFLICTING/DIRTY` today; whichever merges second re-measures.
- Phase 0 task 0.4 has work re-measure the byte count after rebasing onto `origin/main` and record the number,
  even though no edit is planned (if #11551 merges first the number moves and the gate's headroom changes for
  everyone).

## Implementation Phases

Order follows `cq-write-failing-tests-before`: in this PR the tests ARE the deliverable, so each phase writes
its controls first, proves them RED against the pre-implementation suite (function absent, or a scratch
mutation), then implements. All edits go to the one suite file; re-read it before each phase (line numbers
move; locate by content anchors). Plan-review revision (2026-10-30): the cross-check, the command-position
grammar, `sumkeys`/pairwise controls and the must-pass nested tree were cut or reshaped; see
`decision-challenges.md` (S1-S4).

### Phase 0 — Preflight (no edits)

- 0.1 Re-read `tests/scripts/test-registry-d10-workflow-wiring.sh` (W9 block), `tests/scripts/lib/restore-engine-header.sh`
  and the engine header. Re-count the header's failure codes from the live file with
  `source tests/scripts/lib/restore-engine-header.sh; restore_header_codes < scripts/registry-restore-from-ghcr.sh`
  (expect `1 2 3 4 5 6 78`, 7 codes). Do not trust the numbers in this plan.
- 0.2 `git fetch origin main`, `git rebase origin/main` (no stash). Re-confirm each item is still stale with
  `git grep -n 'does not list it\|fewer than 6' origin/main -- tests/scripts/test-registry-d10-workflow-wiring.sh`
  and `git grep -in 'restore summary' origin/main -- tests`.
- 0.3 Baselines (each its own Bash call, detached with an rc file where long): wiring 47/0, pull-path-health
  63/0, restore-from-ghcr 98/0, `bun test plugins/soleur/test/workflow-file-size.test.ts`. If the local battery
  queues behind another worktree (rc 6), stop waiting: CI's required `test` context is the authority and is
  never labelled passed locally.
- 0.4 Re-measure `wc -c .github/workflows/apply-web-platform-infra.yml` after the rebase and record it (expected
  489,131 unless #11551 or another PR changed it). Record `git diff --stat origin/main...HEAD -- .github` empty.
- 0.5 Measure the cost of W1-W8 (needed for Phase 3.3; CTO threshold ~5 s): in a sandbox copy of the suite, add
  `date +%s` stamps before W1 and after W8 and run it once; record the seconds.

### Phase 1 — Guard 2: computed `die`/`exit` word census (residual 3b)

- 1.1 RED first: in a sandbox copy (`scripts/soleur-sandbox.sh new w9-census`), add the controls (below) that call
  `w9_computed_sites`; run: they fail because the function is absent.
- 1.2 Implement `w9_computed_sites` (engine text on stdin; prints one offender per line as `<line>:<token>`):
  (a) blank, never delete, whole-line comments (`sed -E 's/^[[:space:]]*#.*$//'`) so line numbers match the engine file;
  (b) remove the two allowed line shapes, each required to occur exactly once, by anchored whole-line match:
  the definition `^die\(\) \{( #.*)?$` (its trailing comment is tolerated by the pattern; comments are not
  stripped in general) and `^[[:space:]]*exit "\$code"$` (the `die()` implementation). Zero or two occurrences of
  either is itself an offender line ("allowed site count");
  (c) token pass `grep -noE '\b(die|exit)\b( [0-9]+\b)?'` over the rest; a token is accepted iff it is `die N` /
  `exit N` with exactly one space and digits (the lib extractor's literal shape); every other token is an
  offender. Token level, so a line holding a literal and a computed site reports the computed one. `\b` excludes
  `verify_die` and `exit_code`; `$exit`, `builtin exit "$c"`, `trap 'exit "$c"' ERR` and `die  7` all red (fail closed);
  (d) a floor: fewer than 1 accepted token adds the problem "census inspected zero sites — vacuous".
  Measured at plan time on the live engine: 82 accepted tokens, 0 offenders.
- 1.3 Wire into `w9_check`: `w9_check` calls the same `w9_computed_sites` (not a copy) and adds a problem
  naming "computed die/exit site" plus the offender lines.
- 1.4 Committed controls: computed variable (`die "$c" "x"`), bare `exit`, case-arm `NETWORK) die "$c" "x" ;;`,
  two-space `die  7 "x"`, zero-sites floor (empty text) — each calls `w9_computed_sites` directly (cheap; the
  appended line must differ from the engine text: the landing check for engine-text controls) — plus ONE
  wire-in control through full `w9_check` (computed die appended, expecting "computed"). The remaining matrix
  rows are run once in the sandbox (Phase 5.2) and listed in the PR body.

### Phase 2 — Guard 1: "Restore summary" step (residual 3a)

- 2.1 RED first: controls call `w9_summary_check` (absent) -> fail.
- 2.2 `W9_PY` modes (new modes dispatch BEFORE the existing `78)`-arm search at the top of the mutate block —
  that search does `.group(1)` on a `None` for this step and would crash every summary control; and the summary
  controls use their own loop with the step name "Restore summary", not `"$RESTORE_STEP"`): `sumextract` (prints
  the run body; exit 3 none, 4 duplicated or outside job `registry_store_restore`, 6 not after the restore
  step in `steps` order), `sumenv` (prints `k=v`, sorted), `sumkeys` (prints which of `continue-on-error shell
  working-directory timeout-minutes` are present and `if=<normalized>`). Do not reuse `keys` (it forbids `if`).
- 2.3 `w9_summary_check <workflow text>` (separate function, not part of `w9_check`): pins `if` exactly `always()`;
  env exactly `RESTORE_RESULT=${{ job.status }}`; no forbidden step keys (pinned in code, no dedicated
  control); position after the restore step; runs the body under `env -i PATH=<minimal> RESTORE_RESULT=<v>
  GITHUB_STEP_SUMMARY=<tmpfile> bash -e -c "$body"` (`bash -e` is the Actions default without a `shell:` key)
  for `success`, `cancelled` and the EMPTY string (stands in for `failure` and every other value through the
  shared `*)` arm; the empty-vs-unset difference is stated: an unset variable behaves the same here because the
  body has no `set -u`); asserts stdout empty, summary file non-empty, heading `## registry store restore`;
  success has `closed` and not `failed`; cancelled has `cancelled` and not `closed`; empty has `failed` and not
  `closed` (whole word `failed`, never `fail`: the cancelled prose says "fail for others"). Semantic anchors,
  not the full prose. No pairwise-differ check (the per-outcome anchors imply it).
- 2.4 Real row `W9s the Restore summary step ...` plus four-plus-one controls as `mutate:sum*` modes, each
  asserting exactly one anchor match then the mutation-landed row: `sumifdrop`, `sumenvlit`, `sumswap`,
  `sumredirect`, `sumorder` (kept: a summary before the restore step reads `job.status` early and misreports).
  Messages are split so no two controls share a fragment (see the Guard Contract).

### Phase 3 — Guard 3: verdict swap (residual 3c)

- 3.1 RED first, by hand in a sandbox copy: change the W9 row to `if true` and the row's `-z` to `-n`; record
  that the current suite stays 47/0 (the defect, quoted in the PR).
- 3.2 `w9_expect <needle> <out>` prints `ok` or `fail` (data, not an exit: it is used inside `$( )`). The controls
  loop reports `_report "<label>" "$(w9_expect ...)" "<detail>"`. The W9 row's verdict goes through the same
  data-returning function shape. Canary row: a known-bad input must come out `fail`, a matching one `ok`.
- 3.3 `W9_NESTED=1`: placed right after the W9 row's `_report` and before the controls loop, `exit 64`. Nested mode
  skips the controls loop, the census/summary controls, the meta-control and the floor, and can never exit 0 (an
  operator exporting the variable in the outer environment gets a run that cannot go green). If Phase 0.5 shows
  W1-W8 cost more than ~5 s, gate them under the guard too.
- 3.4 Meta-control (after the existing "engine-extra-code" control, before the floor, only when `W9_NESTED` is not
  1). Build the tree under `"$W9_TMP/meta"` (NOT a new `mktemp -d` with its own trap: bash keeps one EXIT trap and
  the suite already installs `rm -rf "$W9_TMP"`), `assert_fixture_dir` it, copy the suite itself
  (`"${BASH_SOURCE[0]}"` at `tests/scripts/`), `tests/scripts/lib/restore-engine-header.sh`, the engine,
  `scripts/derive-app-domain-base.sh` (executable), `.github/actions/` and the `drop1`-mutated workflow at
  `.github/workflows/`. Run `W9_NESTED=1 timeout 120 bash <copy>`. Mutated tree only (CTO S1): require exit 64
  (a crash or a missing-file `exit 2` fails here), `cmp` shows the nested workflow differs from the real one
  (mutation landed), exactly one `  FAIL ` line, and it names `W9 the restore step maps` and `exit 1 fell`
  (so a partial copy failing some other W-row cannot masquerade as the swap being caught). The must-pass tree
  is not built: the outer real row proves the real tree prints ok, and a hardcoded-FAIL row reds the outer run.

### Phase 4 — Wording and header block (residual 2)

- 4.1 Reword the comment at the "Exit 1 is added to the tested population (the header does not list it)" anchor:
  exit 1 is always in the tested population (header UNION {1}), exercised and barred from the `*)` arm even if the
  header row for 1 were dropped, and its annotation must name the manifest.
- 4.2 Message `fewer than 6 failure codes` -> `fewer than 7 failure codes`. Keep `-ge 7`, the `grep -vx 1` ignore
  and "both without 1".
- 4.3 Edit only the two header-block sentences that become false (CTO F4): rewrite "NOT covered here" to state
  what is covered now (summary step, computed sites, verdict swap) and the true residue (engine prose; a die
  whose code arrives via `eval` or an indirect call such as a command held in a variable); narrow "A text parse
  of the `case` was bypassed ... none is kept" to the workflow's `case`. Do not re-document the block.
- 4.4 Recount `EXPECTED_ASSERTIONS` from a green run (provisional estimate ~62: 47 + summary row and 5 controls
  + census 6 controls + canary 1 + meta 1; the green run decides) and keep it EXACT.

### Phase 5 — Verify, mutation-prove, stop

- 5.1 Run the four gates (each its own Bash call; long ones detached with an rc file; read the log before
  reporting a gate as running).
- 5.2 Mutation-prove on a sandbox copy (`scripts/soleur-sandbox.sh new w9-residuals`), restoring from a pristine
  copy kept beside it, never `git checkout`: every Guard Contract row not committed as a control, plus the
  harness rows. Record rows and outcomes in the PR body.
- 5.3 Pre-ready gates (previous PRs on this suite): `python3 -I scripts/ci-pr-affected-replay.py ratchet`;
  `python3 -I scripts/lint-infra-no-human-steps.py --changed --base origin/main`;
  `python3 -I scripts/lint-guard-contract.py <this plan>`; secret scan before every push. The advisory
  `affected-index-ratchet` red is known and unrelated; do not chase.
- 5.4 PR body (`Ref #10932`, `Ref #9757`, never a closing keyword; PR stays DRAFT). FIRST LINE: "Merging this PR
  mutates no production system: it edits only `tests/scripts/test-registry-d10-workflow-wiring.sh` and planning
  artifacts, none of which is in `apply-web-platform-infra.yml`'s push `paths:` filter (`apps/web-platform/infra/**`,
  the workflow file itself, `tests/scripts/lib/destroy-guard-filter-web-platform.jq`), and the engine and lib
  bytes are unchanged so the ~860 s registry battery is not armed." Then: states residual 2 fixed
  against the live header count; 3a/3b/3c each closed and how; "no sub-item dropped"; "no workflow edit, no
  production apply fired, byte count re-measured: <n>"; "engine and lib untouched (CTO F2/F2b)"; accepted
  residue (loose "step above" text, stale lib sentence about computed dies, a hardcoded verdict at the controls
  loop's call site); and plainly: this does NOT clear every residual on #10932 (the `grep -vx 1` ignore and the
  engine-owned wording remain) — ask the operator before closing #10932.

## Guard Contract

### Guard 1 — W9s: the Restore summary step

**Property.** After a restore that failed, was cancelled or succeeded, the job's summary step runs and writes the
matching outcome block to `$GITHUB_STEP_SUMMARY`, and nothing else; no edit to its trigger, input, position or
outcome arms can change that without a PR check turning red.

**Assembly.** One step, found by exact name, unique, inside job `registry_store_restore`, after the restore step.
Pinned surfaces: `if`, `env` (exact set), forbidden step keys (code pin), step position, and the run body
executed for `success`, `cancelled` and the empty string. `job.status` takes `success`/`failure`/`cancelled`;
`failure` and any other value share the `*)` arm with the empty string. The body writes through one grouped
redirect. The pins and the controls flow through the single `w9_summary_check` chokepoint.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the step's `if: always()` (control `sumifdrop`) | RED naming "summary step if" |
| 2 | `RESTORE_RESULT: ${{ job.status }}` -> literal `success` (control `sumenvlit`) | RED "summary step env" |
| 3 | Swap the success and `*)` arm texts (control `sumswap`) | RED "summary outcome success" and "summary outcome failed" |
| 4 | Remove the `>> "$GITHUB_STEP_SUMMARY"` redirect (control `sumredirect`) | RED "summary stdout" |
| 5 | Move the summary step before the restore step (control `sumorder`) | RED "summary step position" |
| 6 | Second member after a compliant first (sandbox row): correct `if`, env changed | RED "summary step env" |
| 7 | `if: always()` -> `if: success()` (sandbox row) | RED "summary step if" |
| 8 | Add `continue-on-error: true` (sandbox row; code pin, no committed control) | RED "summary step keys" |
| 9 | Empty the `*)` arm (sandbox row) | RED "summary outcome failed" |
| 10 | Own dispatch: rename the step so extraction finds none (sandbox row) | RED (extract rc), not a silent pass |

Harness rows: removing the env assertion from `w9_summary_check` must turn `sumenvlit` RED; replacing the body
execution by a fixed string must turn `sumswap` RED. Must-PASS non-canonical input: the same workflow with the
success text reworded (still containing `closed` and not `failed`) and the env keys in a different order must
pass.
Anchor: the expected `if`/env literals live in the suite; changing the workflow and the suite in one commit is a
reviewable pair, which is the integrity limit of a consistency pin (stated, not hidden). The outcome anchors are
semantic words, not prose.

### Guard 2 — W9c: computed `die`/`exit` word census

**Property.** Every `die` and `exit` word in the restore engine's code is either a literal-code site the header
extractor sees, or one of two allowed lines (the `die()` definition and its `exit "$code"`); anything else turns
the W9 check red.

**Assembly.** The engine text with whole-line comments blanked. The chokepoint is `w9_computed_sites`, called from
`w9_check` (the main W9 row, the wire-in controls and the nested run all go through it). The census is over WORDS
(`\b(die|exit)\b`), not over call positions, so `builtin exit "$c"`, `trap 'exit "$c"' ERR`, `$(die ...)`, case
arms and `&&`/`||` chains are all covered with no anchor set to under-enumerate. A wrapper's own `die`/`exit` is a
word, so wrappers are covered (`verify_die` calls `die` with literal codes today and is excluded as a word by
`\b`). The stated residue is an indirect call (`eval`, a command held in a variable). A prose word `die`/`exit`
in code (a message string, an inline comment) reds: fail closed, reword it.

**Mutation matrix:**

| # | Mutation (appended to / applied on engine text) | Expected |
|---|---|---|
| 1 | `die "$c" "x"` (control) | RED "computed die/exit site" |
| 2 | bare `exit` (control) | RED |
| 3 | `NETWORK) die "$c" "x" ;;` case arm (control) | RED |
| 4 | `die  7 "x"` two spaces, invisible to the extractor (control) | RED |
| 5 | Own dispatch: census on empty text (control) | RED "inspected zero sites — vacuous" |
| 6 | Wire-in: computed die appended, full `w9_check` (control) | RED naming "computed" |
| 7 | Second member after a compliant first: `die 3 "x" \|\| exit "$c"` (sandbox row) | RED (token level) |
| 8 | A second `exit "$code"` (sandbox row; allowed-site count must be exactly 1) | RED "allowed site count" |
| 9 | `exit $?`, `builtin exit "$c"`, `trap 'exit "$c"' ERR` (sandbox rows) | RED |
| 10 | Trailing inline comment containing `exit 3` on a code line (sandbox row) | RED (fail closed by design) |

Harness rows: deleting the `w9_computed_sites` call from `w9_check` must turn control 6 RED; replacing the
function body by `true` must turn controls 1-4 RED. Must-PASS inputs that are not the canonical engine: appended
literal `die 7 "x"` and a whole-line comment `# exit $x` must NOT trip the census (and the existing
engine-extra-code control still goes red only via "differs").
Anchor: the two allowed line shapes and the literal shape are literals in the suite; the engine is held
byte-unchanged by a merge-base `git diff --stat` AC, the anchor outside the suite.

### Guard 3 — W9v: verdict swap

**Property.** If the W9 check finds a problem, the suite prints a FAIL row naming it and the nested proof reds if
the W9 row cannot; the verdict function used by the row and by the controls loop maps a missing needle to `fail`.

**Assembly.** Two verdict sites: (i) the real W9 row, proved end-to-end by the nested run of the suite copy on a
`drop1`-mutated tree; (ii) the verdict function `w9_expect` used by the controls loop and the row, proved by a
canary. A hardcoded verdict at the loop's call site is the stated, accepted residue. The nested run cannot rely on
the outer environment: `W9_NESTED=1` always exits 64.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | W9 row `if [[ -z "$w9_problems" ]]` -> `if true` (sandbox row) | RED: meta-control (nested mutated tree prints ok, expected a FAIL line) |
| 2 | `-z` -> `-n` (sandbox row) | RED: meta-control (outer real row also red) |
| 3 | The row's else-arm `fail` -> `ok` (sandbox row) | RED: meta-control |
| 4 | Row hardcoded to `_report ... ok`, assertion count unchanged (sandbox row) | RED: meta-control (a floor-only guard stays green) |
| 5 | `w9_expect` always prints `ok` (committed canary) | RED: canary |
| 6 | Own dispatch: remove the `exit 64` sentinel so nested exits 0 (sandbox row) | RED: meta-control exit-code check |
| 7 | Second member: the loop verdict hardcoded at its call site (sandbox row) | NOT detected — accepted residue, stated in the PR body |
| 8 | Nested copy missing `.github/actions` (sandbox row) | RED via nested `exit 2` (missing bridge file); a partial copy that only fails another W-row is RED via the FAIL-line check |

Harness rows: removing the `cmp` mutation-landed check must let a no-op mutation pass (verified by a scratch
edit), so the check is load-bearing and is part of the committed meta-control. Must-PASS: the outer real tree
printing the exact ok W9 row is the must-pass input (no second nested tree).
Anchor: the sentinel 64 and the exact row/fragment text live in the suite; the real workflow is the nested run's
input, so the proof is relative to the repo's own artifact, not to a stored copy.

## Ship constraints

- No `gh pr ready`, no auto-merge by this planning session; PR #11589 stays DRAFT until the ship phase.
- PR body: `Ref #10932`, `Ref #9757`; never `Closes/Fixes/Resolves` (replace the ship skill's default). Do not
  touch #11312, #11379, #10924. Do not close #9757 or #10932.
- Never `git stash` (use a WIP commit); no `pgrep -f`; secret scan before every push; long gates detached with
  an rc file, one Bash call per gate; if the local battery queues (rc 6) CI's required `test` context is the
  gate and is never labelled passed locally. Known unrelated red: advisory `affected-index-ratchet`.
- Mutation proofs only in a `soleur-sandbox.sh` copy, restored from a pristine copy.

## User-Brand Impact

- **If this lands broken, the user experiences:** a test-only change; the worst case is a flaky or wrongly red PR
  check on the wiring suite (CI noise for contributors) or a guard that silently asserts less than it claims. No
  runtime behaviour of the registry restore changes.
- **If this leaks, the user's workflow is exposed via:** no vector — the suite stubs `doppler` and the engine, uses
  synthesized values, reads no credential and no network resource.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff changes no production code, workflow, script or secret path;
  the registry restore itself is untouched, and the guard it strengthens protects an operator-facing annotation.

## Observability

```yaml
liveness_signal:
  what: the wiring suite's W9 row and its controls, run by CI's required test context on every PR touching the suite, the engine, the lib or the workflow
  cadence: per-PR
  alert_target: the failing required PR check
  configured_in: scripts/test-all.sh (run_suite tests/scripts/registry-d10-workflow-wiring)
error_reporting:
  destination: CI check output (FAIL rows with problem text)
  fail_loud: the suite exits 1 and prints "FAIL W9 ... — <problem>"
failure_modes:
  - mode: a die/exit with a computed code is added to the engine
    detection: the W9c census problem naming the token and line
    alert_route: PR check failure
  - mode: the summary step loses `if: always()` or its outcome text is mislabelled
    detection: the W9s pins and the executed-body assertions
    alert_route: PR check failure
  - mode: the W9 verdict is swapped to pass
    detection: the nested meta-control
    alert_route: PR check failure
logs:
  where: CI run log of the required test context
  retention: GitHub default run-log retention
discoverability_test:
  command: grep -c "^w9_computed_sites()" tests/scripts/test-registry-d10-workflow-wiring.sh
  expected_output: 1
```

## Verification

```bash
cd /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-10932-residuals-2-3-restore-w9
bash tests/scripts/test-registry-d10-workflow-wiring.sh          # ends "=== N passed, 0 failed ===" with N = the new EXPECTED_ASSERTIONS
bash tests/scripts/test-registry-pull-path-health.sh             # 63/0, unchanged
bash tests/scripts/test-registry-restore-from-ghcr.sh            # 98/0, unchanged
bun test plugins/soleur/test/workflow-file-size.test.ts          # passes; workflow bytes unchanged
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git diff --name-only origin/main...HEAD` is a subset of: `tests/scripts/test-registry-d10-workflow-wiring.sh`,
  this plan, `knowledge-base/project/specs/feat-one-shot-10932-residuals-2-3-restore-w9/{tasks,decision-challenges,session-state}.md`,
  and `knowledge-base/INDEX`-style generated files if the pipeline regenerates one.
- [ ] `git diff --stat origin/main...HEAD -- .github scripts apps tests/scripts/lib tests/scripts/test-registry-pull-path-health.sh tests/scripts/test-registry-restore-from-ghcr.sh` prints nothing.
- [ ] `wc -c .github/workflows/apply-web-platform-infra.yml` equals the Phase 0.4 measurement taken after the
  rebase (no edit) and is <= 490,000; `bun test plugins/soleur/test/workflow-file-size.test.ts` passes.
- [ ] `git grep -n 'does not list it' -- tests/scripts/test-registry-d10-workflow-wiring.sh` prints nothing and
  `git grep -n 'fewer than 6' -- tests/scripts/test-registry-d10-workflow-wiring.sh` prints nothing;
  `git grep -c 'fewer than 7 failure codes' -- tests/scripts/test-registry-d10-workflow-wiring.sh` prints `1`;
  the `-ge 7` guard and the `grep -vx 1` ignore are unchanged.
- [ ] `bash tests/scripts/test-registry-d10-workflow-wiring.sh` ends `=== N passed, 0 failed ===` where N equals
  `EXPECTED_ASSERTIONS` (count taken from the green run; the RED runs in Phases 1-3 are shown first in the PR).
- [ ] `bash tests/scripts/test-registry-pull-path-health.sh` ends 63/0 and `bash tests/scripts/test-registry-restore-from-ghcr.sh` ends 98/0 (unchanged inputs).
- [ ] Every Guard Contract row not committed as a control was run once on a sandbox copy (pristine copy restored
  between rows) and its outcome is listed in the PR body; every committed workflow-mutating control passes the
  "mutation landed" check, every committed engine-text control asserts its appended line changed the text, and
  each control names a fragment only its own pin produces.
- [ ] The wiring suite's added wall time is recorded in the PR body (baseline 52 s; target < 90 s).
- [ ] `python3 -I scripts/lint-guard-contract.py` passes on this plan; `python3 -I scripts/lint-infra-no-human-steps.py --changed --base origin/main` passes.
- [ ] The PR body's first line states that merging mutates no production system and why (the `paths:` filter, engine and lib byte-unchanged).
- [ ] PR body carries `Ref #10932` and `Ref #9757`, no closing keyword; states "no sub-item dropped", the accepted
  residues, and that #10932 is NOT fully cleared (two items remain), asking the operator before closing it.
- [ ] Decision rows in `decision-challenges.md` all pass the ruling gate (`| Item | Class | Ruling |`).

### Post-merge (operator)

- [ ] None required. No workflow edit means no merge-triggered production apply from this PR. After merge the operator
  decides whether to close #10932 (two items remain: the `grep -vx 1` ignore, engine-owned wording).

## Test Scenarios

- Given the unedited engine, workflow and suite, when the suite runs, then the W9 row, `W9s`, the census and the
  meta-controls all pass and the count equals `EXPECTED_ASSERTIONS`.
- Given `die "$c" "x"` appended to the engine text, when `w9_check` runs, then it reports "computed die/exit site".
- Given a workflow whose summary step lost `if: always()`, when `w9_summary_check` runs, then it reports
  "summary step if".
- Given the W9 row edited to `if true`, when the suite runs on the real tree, then the meta-control fails.
- Given `W9_NESTED=1` exported in the outer environment, when the suite runs, then it exits 64 and never 0.
- Given a header that loses its row for exit 1, when the suite runs, then it stays green on the comparison (the
  `grep -vx 1` ignore is unchanged and recorded as a remaining residual), and exit 1 is still exercised.

## Non-Goals

- Dropping the `grep -vx 1` ignore (separate follow-up on #10932; test logic outside the brief).
- Engine-owned wording ("Nothing was copied", arm 3 "The store is EMPTY"): needs an engine edit that arms the battery.
- Fixing the summary failure arm's loose "The step above emitted one ::error::" wording (CTO F1b).
- Any edit to the lib, the engine, the workflow, the rationale doc or the runbooks.
- Covering indirect `die` calls (`eval`, a command held in a variable).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — test-only change to an infrastructure guard suite.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan` Phase 4.6; this one is
  filled (threshold `none`; the touched path is not on the sensitive-path regex).
- `scripts/lib/test-affected-paths.sh` is a `PR_GATE_MACHINERY` member: if the affected-index audit asks for a
  declared-edge entry for the wiring suite (it already names `tests/scripts/lib/restore-engine-header.sh`,
  `scripts/registry-restore-from-ghcr.sh`, `scripts/derive-app-domain-base.sh`), do not edit that file blindly —
  editing it arms every battery; escalate to a CTO ruling instead.
- The nested run re-runs W1-W8 in its copy; measure first and gate those rows under `W9_NESTED` if they cost more
  than ~5 s (Phase 0.5 / 3.3). Build the nested tree under `"$W9_TMP/meta"`: bash keeps one EXIT trap and the
  suite already installs `rm -rf "$W9_TMP"`.
- New `mutate:sum*` modes must dispatch before the existing mutate block's `78)`-arm search (it raises on the
  summary step's segment), and the summary controls pass the step name "Restore summary", not `"$RESTORE_STEP"`.
- `w9_expect` is used inside `$( )`; it must print a verdict and never `exit` (an `exit` there exits only the subshell).
- Anchors for the census and summary pins use `once()`-style uniqueness (exactly one match) so a mutator that
  silently matches zero or two places fails the "mutation landed" row instead of passing for the wrong reason.
- Any `die`/`exit` word in engine code that is not a literal site or one of the two allowed `die()` lines reds
  (a message string, an inline comment, `$exit`); fail-closed by design — reword it, never strip comments in the
  check.
- Re-read the suite before each phase: the W9 block is edited in several places and line numbers move.
- The assertion count is exact; recount from a green run after the last edit, not from this plan's estimate.
