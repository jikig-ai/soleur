---
title: "chore: grep -q pipe-guard series, slice S7a (codemod and guard cleanup; the producer-side join moves to S7b)"
date: 2026-10-11
slug: grep-q-wave-b-s7-codemod-guard-cleanup
branch: feat-one-shot-grep-q-wave-b-s7-codemod-guard-cleanup
issue: 9217
type: chore
lane: single-domain
---

## Enhancement Summary

**Deepened on:** 2026-10-11. **Method:** plan-review panel (simplicity, correctness, devex seats) applied; deepen-plan mechanical halts run (user-brand, PAT, Guard Contract lint, Scope Check schema); the all-agent fan-out was not run because each mechanism had already been checked against the real guard by three seats.

- Corrected the table count (twelve rows, not eight), cut the self-referential `codemod-gone` check and the no-op `exit 1` pin, switched the test canaries to a separate listing (the `SWEEP_CANARIES` loop also runs on every fixture root), narrowed the `_ts_re` directory alternative, anchored the wiring pins so they cannot count themselves, and rewrote Scope Check to the schema.

## Overview

Slice S7 of the grep -q pipe-guard series (tracker #9217; also #7376, #6601, #7797, #9482). S1 to S6 are merged, and
the counted deferral table now holds eight rows: two data-pin rows (`.claude/*.test.sh` at 5, `plugins/soleur/test/*` at 5) and the
six file-exact carrier rows under `apps/web-platform/infra/`. No row remains for the codemod to act on, so this slice removes the series'
own instrument and hardens the guard it leaves behind. The producer-side join (Arm P) is cut into its own PR, S7b, and recorded as a
decision challenge (user-challenge: the brief names both under S7; the split follows the scope check below).

This PR (S7a) delivers five things, each owned by one Guard Contract entry or one deletion:

1. Delete `scripts/grep-q-drain-codemod.py` and the guard's codemod selftest block (29 probe checks), and move `SWEEP_PROBE_CHECKS` by the measured number.
2. Replace the two glob rows with six file-exact `=` rows (one per file, ten hits), widen `_ts_re` so a glob-free test path classifies as test-shaped, and drop the dead `^scripts/(lib/)?test-\*$` alternative. This closes the add-one-delete-one hole the guard header names. The table then holds twelve rows (six exact test rows, six carrier rows).
3. Add test-shaped canary paths (a population floor by identity, derived by a separate listing with the sweep's own pathspec) so a `.gitignore` entry or pathspec exclusion hiding only `*.test.sh` files under a swept root turns the guard red (decision-challenges item 24 of S6).
4. Pin the guard's own top-level wiring (`|| sweep_rc=$?` and `sweep_fold "$sweep_rc"`), unpinned today (named in S6's NOT-fixed list). The probe verdict gate's `exit 1` is not pinned: the arm sets `FAIL=1` and the file ends with the already-pinned `exit "$FAIL"`, so removing it changes no exit status (review finding; cut).
5. Rewrite the header and row commentary to the S7a state (the series is not finished while S7b is open), including a one-line command to recompute `SWEEP_PROBE_CHECKS`.

## Research Insights

Premise validation (Phase 0.6). Checked against `origin/main` at `3eb0238125`:

- `#9217`, `#7376`, `#6601`, `#7797`, `#9482` are open; no open PR touches the guard or the codemod (`gh pr list` file probe returned none); no open code-review issue names a planned file (the only hit for the touched test files is `#8659`, a different concern, acknowledged).
- The deferral table has exactly the eight rows above (`bash .claude/hooks/grep-q-pipe-guard.test.sh` prints eight `DEFERRED:` lines; ceiling total 10).
- Hit locations under the two data-pin rows (code lines, comments and marked lines dropped, `git grep -nE` with `PATTERN_V2` over the two globs): `.claude/hooks/background-poll-prefer-monitor.test.sh:84`, `.claude/hooks/pkill-self-match-guard.test.sh:223,224,225,280` (5 hits, 2 files); `plugins/soleur/test/deploy-arm-mutations.sh:73`, `deploy-arm.test.sh:676`, `ship-phase-7-poll-fixtures.test.sh:215`, `worktree-manager-porcelain-sigpipe.test.sh:229,236` (5 hits, 4 files; `ship-learning-probe.test.ts:214` is a `.ts` file the sweep does not cover).
- The codemod has no caller: `git grep -l grep-q-drain-codemod -- . ':!knowledge-base' ':!.claude/hooks/grep-q-pipe-guard.test.sh'` returns only the tool itself. The selftest is guard lines 1051 to 1392 (29 `sweep_probe_fail+=(` checks, the `codemod-*` and `verify-*` families) out of 62 pinned.
- The producer-side join is real work: 40 candidate `(printf|echo|cat) ... | <verb>` lines over production roots, about 29 after dropping fixtures, `.py` and `.ts` files (J0 below), spread over 20 files and their owner suites. That is a separate PR.

Property List (Phase 0.6b):

- P1. A counted deferral cannot move between files without the guard going red.
- P2. A subtree's test files cannot silently leave the sweep (ignore entry, pathspec exclusion) without the guard going red.
- P3. The guard's verdict reaches its exit code through wiring a text edit cannot remove unnoticed.
- P4. No dead instrument (codemod, selftest, dead classifier clause) remains, and the commentary describes the final state.

Cut List (Phase 0.6b), each cut names the property it would have bought and what covers it:

- Derived replacement of `SWEEP_CANARIES`, the 31 `real_paths` plants and `GATED_TEST_ROWS` (S6 item 6): cut. P1 and P2 are met by the file-exact rows and the canary paths; a derived assertion would move `SWEEP_PROBE_CHECKS` again without buying a property the pins lack. Recorded as NOT fixed with the three-instance list.
- A per-root count floor on swept `*.test.sh` files: cut. A `>=` floor survives any substitution that keeps the count; the canary-by-identity form covers the hiding mutation and needs no measured number that rots. (Measured at work for the evidence file only.)
- Per-subtree marker count pin (series Item F): not in this slice; Item F is its own PR in the brief. The marked-line count (34 repo-wide, 9 in the guard file itself) is recorded in the evidence file as the baseline.
- A permanent `codemod-gone` probe check (and its mutation rows): cut at review. A re-added tool arrives as a file in a diff, the tool has no caller, and the check's own text would contain the token it asserts absent. AC-2 verifies the absence once.
- A pin on the probe verdict gate's `exit 1`: cut at review (behavioural no-op; see Overview item 4).
- A wall-time measurement as an acceptance criterion: cut (depends on machine load); the number may appear in the evidence file as context only.
- Removing the six carrier rows: gated on a host replace (ADR-100, ADR-169); stays.

Value-proposition measurement (Phase 0.6c): the saving claimed is ownership cost (a 785-line tool plus a 342-line selftest, 29 of 62 probe checks, that no row can exercise). Measured by `wc -l scripts/grep-q-drain-codemod.py` (785) and the guard line range above; the guard's run time with the selftest is about 7 s of which the selftest share is measured at work and recorded, not asserted here.

## Research Reconciliation: Spec vs. Codebase

| Claim | Reality | Plan response |
| --- | --- | --- |
| Brief: S7 is "producer-side join, codemod and guard cleanup" in one PR | J0 measures about 29 production sites over 20 files, each needing owner-stub edits in suites S2 to S6 already touched, plus a new `PRODUCER_JOIN` table and its own Guard Contract; the cleanup is guard-only | Split: S7a (this PR) is cleanup; S7b is the join. Decision-challenge recorded (user-challenge, small) |
| Series plan: "S7 deletes the codemod once no glob row is left" | Two glob rows are left (data pins). They hold no convertible hit: five and five lines inside strings, and the tool's verify cannot act on them | Convert both glob rows to file-exact rows in this slice, then delete the tool. The condition becomes true in the same PR |
| Guard header: "`_ts_re` classifies a file-exact test path as a PRODUCTION row, so a `_ts_re` widening is reviewed on its own; the last Wave B slice revisits it" | `GATED_PROD_ROWS=6` counts every non-test-shaped row; a file-exact `.test.sh` path matches no alternative today | Widen `_ts_re` with one alternative for a glob-free path ending `.test.sh` or sitting under a `test/` or `tests/` directory, and prove the six production rows stay production (mutation row M5) |
| S6 NOT-fixed: guard top-level wiring unpinned | `|| sweep_rc=$?` (line 593) and `sweep_fold "$sweep_rc"` (line 594) each appear once outside comments before any pin exists | Pin each as an anchored full statement whose own pin line cannot match it (pattern assembled from two parts), so the count stays exactly 1 after the pin lands |
| S6 item 24: a `.gitignore` entry hiding only `*.test.sh` files stays green | Measured in S6 (rows 13d to 13f): the root canary is satisfied by any other swept file | Canary paths by identity (Guard 2). `scan_sweep` prints only `SWEPT: n files` and keeps `$files` local, and its UNRESOLVED canary loop also runs on every scratch-root fixture, so test canaries must NOT join `SWEEP_CANARIES`; they are checked by a separate listing over `.` with the same `SWEEP_PATHSPEC` |
| Plan v1: the table holds eight rows after the slice | Six exact test rows plus the six carrier rows is twelve | AC-1 and Guard 1 say twelve |

## Implementation Phases

Phase 0 (red first, `cq-write-failing-tests-before`). In the guard, before any edit, add the new probe rows (M1 to M14 below) with their expected-RED text and run the guard once from inside the repo, in a checkout whose `git status --porcelain` is empty (the sweep reads the working tree with `--no-index`, so a stray untracked file changes the hit set), under `ulimit -v 6000000`; record that each new row reads FAIL for the named reason. The rows are the tests; the edits below turn them green.

Phase 1 (D2, rows). Replace `'.claude/*.test.sh | <= | 5 | #9217'` and `'plugins/soleur/test/* | = | 5 | #9217'` by six file-exact `=` rows (`background-poll-prefer-monitor.test.sh` 1, `pkill-self-match-guard.test.sh` 4, `deploy-arm-mutations.sh` 1, `deploy-arm.test.sh` 1, `ship-phase-7-poll-fixtures.test.sh` 1, `worktree-manager-porcelain-sigpipe.test.sh` 2). In `_ts_re`: drop the `^scripts/(lib/)?test-\*$` alternative, keep the two glob alternatives (the loose-row control still uses them), and add two exact-path alternatives: a glob-free path ending `.test.sh` and the glob-free paths under `^plugins/soleur/test/` (narrowed to that one directory, so a future exact production path under some other `test/` directory is not test-shaped). Keep the `tests_rows` check (it guards a resurrected row for the zero-hit `tests/` subtree and is independent of `_ts_re`). Set `GATED_TEST_ROWS` to the six exact paths in table order. Production rows (`GATED_PROD_*`) are unchanged and re-proved by M5. The row commentary states the price of exactness: renaming or splitting one of these six files needs a row edit in the same PR, and the stale-row failure text says "file moved or renamed: update its row".

Phase 2 (D3, canaries by identity). Add `SWEEP_TEST_CANARIES` (four paths, one per root a `*.test.sh` ignore glob could empty: `.claude/hooks/guardrails.test.sh`, `plugins/soleur/test/deploy-arm.test.sh`, `apps/web-platform/infra/ci-deploy.test.sh`, `scripts/actions-queue-health.test.sh`; each verified tracked with `git ls-files`), pinned beside a literal count. Choose files unlikely to be renamed (long-lived suites of load-bearing components) and state the rule in a comment. One new probe check lists the real tree with the same command `scan_sweep` uses (`git -c core.excludesFile=/dev/null grep --no-index --exclude-standard -al -e '' -- "${SWEEP_PATHSPEC[@]}"`) and fails naming each missing canary; a failed listing (rc above 1) is UNRESOLVED and exits 3, never a pass. The canaries do NOT join `SWEEP_CANARIES` (that loop runs on every scratch-root fixture and would mark each UNRESOLVED).

Phase 3 (D4, wiring pins). Add one probe check that counts, over non-comment lines, the anchored full statements `sweep_main . "$SWEEP_FLOOR" || sweep_rc=$?` and `sweep_fold "$sweep_rc"` (each expected exactly once). The pin's own line assembles each pattern from two quoted parts so it cannot match itself. The failure message names what the pin protects (the sweep verdict reaching the exit code), what it expects (the two statements at the top level, once each) and the fix (restore the statement; if it moved legitimately, update the pin, not the sweep).

Phase 4 (D1). `git rm scripts/grep-q-drain-codemod.py`; delete guard lines 1051 to 1392 (the selftest header, `_cm`, fixtures and the 29 checks; nothing after 1392 uses `_cm`, `_cleangit`, `assert_fixture_dir`, `_mkguard`, `_vrepo`, `CM` or `vr`, and `sweeproot`, `okroot`, `_vp`, `sw_roots` are defined above 1051). Recompute `SWEEP_PROBE_CHECKS` from the file (`grep -vE '^[[:space:]]*#' | grep -c 'sweep_probe_fail+='`), never by subtraction alone: expected 33 plus the checks added in Phases 2 and 3. Record the deletion commit SHA in the PR body so the tool can be recovered from history.

Phase 5 (D5, wording). Rewrite the header paragraphs naming the codemod and the KNOWN HOLE, the S6 and S5 row commentary, and the `SWEEP_DEFERRALS` block comment to the S7a state: the codemod is gone, hand conversion with the Rewrite table is the path (S7b is hand conversion), the producer side is still open and tracked on #9217 as S7b. Add one comment line with the command that recomputes `SWEEP_PROBE_CHECKS`. Do not write that the series is finished.

Phase 6 (evidence and learning). Write the spec dir's `evidence.md` (before and after `DEFERRED:` table, the check-count arithmetic, the mutation matrix results, the marked-line baseline), `decision-challenges.md`, and one learning if a non-obvious finding occurs.

## Files to Edit

- `.claude/hooks/grep-q-pipe-guard.test.sh` (rows, `_ts_re`, `GATED_TEST_ROWS`, canaries, wiring pins, selftest block deleted, `SWEEP_PROBE_CHECKS`, header and row commentary)

## Files to Delete

- `scripts/grep-q-drain-codemod.py`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s7-codemod-guard-cleanup/{tasks.md,evidence.md,decision-challenges.md}`
- `knowledge-base/project/learnings/<category>/2026-10-11-<slug>.md` only if a non-obvious finding occurs

Not touched, on purpose: `plugins/soleur/skills/work/SKILL.md`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` (its guard entry is already derived; no path changes), `scripts/lib/scratch-root.sh`, `plugins/soleur/test/skill-body-budget.json`, `plugins/soleur/skills/plan/SKILL.md`, `AGENTS*.md`, every file under `.github/`, the six carrier files, the ten pinned hit lines in their four plus two files (the rows re-own them by path; no edit), the historical `hand-edits.txt` ledgers in earlier spec dirs, and the main checkout's `.mcp.json` and untracked `apps/web-platform/1000:` and `500` files.

## Open Code-Review Overlap

None for the guard, the codemod and the six pinned files. `#8659` names other test suites (EXIT-trap leak) and is acknowledged, not folded.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing; a regression is a CI false-red or false-green on a test-hygiene gate, seen by contributors as a failing `test` check or an unflagged `grep -q` pipe.
**If this leaks, the user's data is exposed via:** no vector; the change reads and edits test text only and handles no credentials or user data.
**Brand-survival threshold:** none
threshold: none, reason: the diff edits one repo-internal drift guard and deletes a repo-internal tool; no runtime, data or credential surface is touched.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Guard Contract

The deliverable is a hardening of the drift guard. One entry per property, matrix written from the design before the edits (trimmed at review: the own-dispatch rows that test the tests rather than a property were reduced to one per guard).

### Guard 1 — deferrals own files, not counts

**Property.** Every sweep hit not on a marked or comment line is owned by a named file at exactly its counted number, so moving a hit between files, adding a row for a new file, or widening a row turns the guard red.

**Assembly.** `SWEEP_DEFERRALS` (twelve rows after this slice: six exact test rows, six carrier rows; all `=` and glob-free), `_ts_re` (the one classifier), `GATED_TEST_ROWS` (test-shaped identity, order), `GATED_PROD_ROWS` and `GATED_PROD_GLOBS` (production identity, count), `_loose_not_test_shaped` and its control, the `tests_rows` check, the owner match inside `sweep_verdict`, the stale-row rule, and the `real_paths` plants with `REAL_PLANTED`. The chokepoint is `sweep_verdict` (it owns every hit); the pins are the three places a row set can drift, all re-pinned together.

**Mutation matrix.** Each row is run one at a time against a scratch copy of the edited guard under `ulimit -v 6000000`; expected result is RED on the named text.

| # | Mutation | Expected RED |
| --- | --- | --- |
| M1 | Move one hit: add a `grep -q` pipe to `.claude/hooks/guardrails.test.sh` and delete one of the four `pkill-self-match-guard.test.sh` hits (net count unchanged) | `outside the deferral table` naming `guardrails.test.sh` (the glob form was green here) |
| M2 | Re-widen to `.claude/*.test.sh | <= | 5 | #9217` and delete the exact `.claude` rows | `real-table-test-shaped` (the pinned identity differs) |
| M3 | Delete one exact row and leave its hit | `outside the deferral table` |
| M4 | Widen `_ts_re` with a realistic over-match (any glob-free `.sh` path) | `real-table-production-rows` (`git-data-bootstrap.sh` and `inngest-luks-cutover.sh` become test-shaped, production count falls from 6 to 4) |
| M5 | Lower the `pkill-self-match-guard.test.sh` ceiling from 4 to 3 | ceiling-exceeded text for that row |
| M6 | Convert the one hit in `background-poll-prefer-monitor.test.sh` and keep its row | `stale deferral` for that row |
| M7 | Own-dispatch: set `SWEEP_DEFERRALS=()` in a control | the six test files' hits are reported undeferred, not "0 checked" |

**Harness rows.** H1 (suite edit that MUST read RED): delete the `loose_ctl` control line; the probe-count pin reads RED. H2 (must-PASS, not the canonical): the same twelve rows with extra whitespace around the pipe separators pass, because the parser trims.

**Anchor.** The pinned set and the table sit in one file, so one diff can edit both; the outside check is the reviewer reading the two-place edit and the evidence file's recorded `DEFERRED:` table. Stated, not claimed as integrity. Set identity (`GATED_TEST_ROWS` string equality) is what blocks a count-preserving substitution.

### Guard 2 — test files cannot leave the sweep

**Property.** For each root a `*.test.sh` ignore glob could empty, a named stable test file is present in the sweep's population, so a `.gitignore` entry or pathspec exclusion that hides only test-shaped files is caught.

**Assembly.** The population derivation (`SWEEP_PATHSPEC`, `.gitignore`, `--exclude-standard`), `SWEEP_CANARIES` (nine roots, unchanged), the new `SWEEP_TEST_CANARIES` (four paths) and its pinned count, and the new probe check's own listing command. The chokepoint is the one listing the new check performs with the sweep's own pathspec array.

**Mutation matrix.**

| # | Mutation | Expected RED |
| --- | --- | --- |
| M8 | In a scratch clone add `*.test.sh` to `.gitignore` | each missing canary path is named |
| M9 | Add `:(exclude)apps/web-platform/infra/*.test.sh` to `SWEEP_PATHSPEC` | the infra canary path is named |
| M10 | Delete one entry from `SWEEP_TEST_CANARIES` alone | the count pin |
| M11 | Own-dispatch: make the listing command fail (rc above 1) | UNRESOLVED, exit 3, never a pass |

**Harness rows.** H3 (suite edit): remove the check's `|| sweep_probe_fail+=` tail; `probe-count` reads RED. H4 (must-PASS non-canonical): a second compliant test file added under a swept root passes.

**Anchor.** The list sits beside its check, so one diff can drop an entry and its pin; the pinned paths' identity is the audit surface, and each is verified tracked at work time. The failure message says "canary moved: update `SWEEP_TEST_CANARIES`, not the sweep".

### Guard 3 — wiring reaches the exit code

**Property.** The sweep's return code reaches the guard's exit status through exactly the two top-level statements the header describes.

**Assembly.** The `|| sweep_rc=$?` capture (line 593), the `sweep_fold "$sweep_rc"` call (line 594), and the final `exit "$FAIL"` (already pinned at line 1034). All in this one file.

**Mutation matrix.**

| # | Mutation | Expected RED |
| --- | --- | --- |
| M12 | Replace `|| sweep_rc=$?` with `|| true` | the wiring pin |
| M13 | Delete the `sweep_fold "$sweep_rc"` call | the wiring pin |
| M14 | Own-dispatch: rename both statements in a control copy | the pin reads 0 and fails, not "nothing to check" |

**Harness rows.** H5: a copy where a statement appears only in a comment must still fail (comment lines excluded). H6 (must-PASS non-canonical): the same statements with different indentation pass (the anchor tolerates leading whitespace).

**Anchor.** Same-file text pins: one diff can delete both a statement and its pin. Stated plainly; the outside check is CI's `test` check running the whole guard.

Guard 4 from the first draft (a permanent check that the codemod stays absent) was cut at review; the deletion is verified once by AC-2.

## Observability

Not applicable: no file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/` code paths, `plugins/*/scripts/` or new infrastructure is created or edited; the deliverable deletes a script and edits one test guard.

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| One PR with the join (S7 as briefed) | About 29 production sites over 20 files plus owner-stub edits in suites S2 to S6 changed, a `PRODUCER_JOIN` table and its own Guard Contract; mixes a text-only guard cleanup with behavioural stub edits; two review surfaces in one panel |
| Keep the codemod "for the carriers" | The six carrier rows are `=` rows the tool refuses to `--write`; it has no caller; unowned machinery |
| Count floor per root instead of canary paths | A `>=` floor survives count-preserving substitution and needs a measured number that rots |
| Derived replacement of canary roots, plants and test-row pin | Moves `SWEEP_PROBE_CHECKS` again without a property the pins lack (Cut List) |
| Keep the glob rows, add the canary only | Leaves the add-one-delete-one hole the header calls a KNOWN HOLE, with the decision about it deferred a second time |

## Scope Check

Required on every plan (plan Phase 2.4; halted at deepen-plan 4.12). Asks are quoted from the run's brief (`[brief]`) and the S6 plan it names (`[doc S6 plan]`).

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the producer-side join, codemod and guard cleanup" [brief] | Phases 1 to 5 (cleanup); join to S7b | mapped |
| 2 | "the dead `test-*` clause and the `_ts_re` clause in the codemod/guard" [brief] | Phase 1 (`_ts_re` edits) | mapped |
| 3 | "the S7 exit wording" [brief] | Phase 5 | mapped |
| 4 | "deleting the S1 codemod selftest as the S6 plan notes" [brief] | Phase 4 | mapped |
| 5 | "S7 may edit scripts/grep-q-drain-codemod.py and the guard" [brief] | Files to Edit, Files to Delete | mapped |
| 6 | "the population floor on swept `*.test.sh` files under `apps/web-platform/`" [brief] | Phase 2 (canary paths by identity) | mapped |
| 7 | "the guard top-level wiring and probe verdict-gate pins" [brief] | Phase 3 (wiring pins) | mapped |
| 8 | "the derived zero-hit assertion replacing the hand-written string and pin rules" [brief] | Cut List in Research Insights | descoped — justification: the file-exact rows and canary paths buy both properties it was for, and a derived assertion would move `SWEEP_PROBE_CHECKS` again with no property the pins lack |
| 9 | "also consider the per-subtree marker count pin (Item F)" [brief] | NOT fixed list | descoped — justification: the brief lists Item F as its own later PR, and the marked-line baseline (34 repo-wide, 9 in the guard file) is recorded for it |
| 10 | "the producer-side join" [brief] | S7b (decision-challenges item 1) | descoped — justification: about 29 production pipes in 20 files plus owner-stub edits and its own Guard Contract; separate review surface, tracked on #9217 |
| 11 | "probe verdict-gate pins" [brief] | Overview item 4 | descoped — justification: the `exit 1` arm is a behavioural no-op (the arm sets `FAIL=1` and the file ends with the already-pinned `exit "$FAIL"`), so a pin buys no property |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.claude/hooks/grep-q-pipe-guard.test.sh` edits (Files to Edit) | "S7 may edit scripts/grep-q-drain-codemod.py and the guard" (ask 5) | asked |
| `scripts/grep-q-drain-codemod.py` deletion (Files to Delete) | "deleting the S1 codemod selftest as the S6 plan notes" (asks 4, 5) | asked |
| Six file-exact rows replacing the two glob rows | "the dead `test-*` clause and the `_ts_re` clause in the codemod/guard" (ask 2) | inferred — justification: the `_ts_re` widening is only needed once a file-exact test path exists, and the guard header names the add-one-delete-one hole as the reason the last Wave B slice revisits `_ts_re` |
| `SWEEP_TEST_CANARIES` and its listing check | "the population floor on swept `*.test.sh` files under `apps/web-platform/`" (ask 6) | asked |
| Wiring pin check | "the guard top-level wiring and probe verdict-gate pins" (ask 7) | asked |
| Header and row commentary rewrite | "the S7 exit wording" (ask 3) | asked |
| `evidence.md`, `decision-challenges.md`, `tasks.md` in the spec dir | "a plain NOT-fixed list" [brief standing constraint] | inferred — justification: the per-PR evidence comment on the tracker cites the spec dir's `evidence.md`, and the pipeline's decision-record contract needs `decision-challenges.md` |

### Split Assessment

- Subsystems touched: 2 — `.claude/hooks/`, `scripts/` (plus the knowledge-base spec dir)
- Planned files: 2 code files (one edited, one deleted) plus 3 spec artifacts | Estimated changed lines: about 450 removed (selftest 342 and codemod 785 counted as deleted lines, about 1130) and about 80 added
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the deleted lines exceed 800 but are one whole-file and one whole-block deletion with no logic to review; the join (S7b) is the split boundary

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC-1 `bash .claude/hooks/grep-q-pipe-guard.test.sh`, run from inside the repo in a checkout with an empty `git status --porcelain` under `ulimit -v 6000000`, exits 0 and prints exactly twelve `DEFERRED:` lines (`... | grep -c '^DEFERRED:'` prints 12), none naming a glob (`.claude/*.test.sh` and `plugins/soleur/test/*` absent).
- [ ] AC-2 `test -e scripts/grep-q-drain-codemod.py` fails, and `git grep -n grep-q-drain-codemod -- . ':!knowledge-base'` prints nothing for non-comment lines (run once; no permanent check).
- [ ] AC-3 `SWEEP_PROBE_CHECKS` equals `grep -vE '^[[:space:]]*#' .claude/hooks/grep-q-pipe-guard.test.sh | grep -c 'sweep_probe_fail+='`, and the number moved by 29 removed plus the checks added in Phases 2 and 3; arithmetic recorded in `evidence.md`.
- [ ] AC-4 The red-first run (Phase 0) is recorded in `evidence.md`: each new row read FAIL for the named reason before its edit landed.
- [ ] AC-5 Mutation rows M1 to M14 and harness rows H1 to H6 are each graded against the committed guard, one at a time under `ulimit -v 6000000`, results in `evidence.md`; a row that cannot be run is listed UNVERIFIED with the reason, never counted as passed.
- [ ] AC-6 M1 (moving a hit between two `.claude` test files) reads RED where the base guard read GREEN, both runs recorded.
- [ ] AC-7 Every new pin's failure message names what it protects, what it expects, and the fix (for example "canary moved: update SWEEP_TEST_CANARIES, not the sweep"; "file moved or renamed: update its row"), checked by reading each message once.
- [ ] AC-8 The cheap repo-global lints pass against the branch's base (`origin/main` at branch creation): `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, shellcheck findings on the guard unchanged from base, `markdownlint --config .markdownlint.json` on changed `.md`, `bash scripts/pre-push-ratchet-lane.sh`. CI's required `test` check is the full-battery gate (no local `--affected`, `--print-selection` or `test-all.sh`).
- [ ] AC-9 PR body: `Ref #9217` (never a closing keyword), a plain NOT-fixed list, a `Filed:` line and a gate-override justification if an issue is filed, Merge Danger (`Undo:` and `Blast Radius:`), Pipeline Tally, Changelog, Model Dissents; names the codemod's last commit SHA for recovery; says S7b is hand conversion; avoids the barred vocabulary and operator-verb bullets; cites the spec dir's `evidence.md`, not this plan's path.

### Post-merge

- [ ] AC-10 `soleur:postmerge`: `deploy-arm.sh find --wait <full sha>`, then `served` reads CONTAINS (this diff touches no release-path file, so the expected finding is that no deploy exists for the merge SHA, recorded as such), then a tracker comment on #9217 with the before and after `DEFERRED:` table, the check-count arithmetic, the matrix results, the NOT-fixed list, and S7b named as the open next slice (the tracker is the re-evaluation record; no new issue).

## NOT fixed here (carried into the PR body and the tracker comment)

- The producer-side join, Arm P (S7b, tracked on #9217; reversible split): about 29 production pipes into stdin-consuming verbs and the owner-stub edits; hand conversion, the codemod is gone.
- The derived replacement of `SWEEP_CANARIES`, the 31 plants and `GATED_TEST_ROWS` (three hand-written instances remain; Cut List); revisit the next time a PR miscounts `SWEEP_PROBE_CHECKS` or a canary list.
- The marker `# sigpipe-demo: intentional` stays uncapped per file (series Item F); the baseline is 34 marked lines repo-wide, 9 in the guard file.
- `PATTERN_V2` spelling gaps and the sweep's extension list; the six carrier rows (23 hits, host-replace gated); the 23 wave A3 carrier sites; the infra half of S6 in no required check; #9638, #9639; Items D, E, F, G, I, H.

## Test Scenarios

- Given the guard after Phase 1, when a `grep -q` pipe is added to a `.claude` test file that no row owns, then the guard fails naming that file.
- Given the guard after Phase 2, when `*.test.sh` is added to `.gitignore` in a scratch clone, then the guard fails naming the missing canary.
- Given the guard after Phase 3, when `|| sweep_rc=$?` is replaced by `|| true`, then the guard fails on the wiring pin.
- Given the repository after Phase 4, when the sweep runs, then no non-comment line outside `knowledge-base/` names the deleted tool.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan`; this one carries `threshold: none` with a reason.
- The probe count is the number of non-comment lines carrying the failure-append tail: removed checks, new checks and the pin's own two lines are all counted. Recompute from the file.
- A text pin counts its own line: assemble each pinned pattern from two quoted parts so the pin cannot match itself, then assert the exact count against the anchored statement.
- The new exact rows are test-shaped by the widened `_ts_re`; a file-exact production path must stay production, which M4 proves with a realistic over-widening, not a match-everything one.
- The sweep reads the working tree (`--no-index`): a stray untracked `.sh` or `.yml` changes the hit set, so run the guard and the matrix from a clean checkout and leave no scratch clone behind (`/var/tmp` has been near full).
- M4 and the loose-row control are separate: a `.*` widening also reddens `real-table-test-shaped`, which is why M4 uses the realistic form.

