---
title: "chore(ci): grep -q drain, Item B slice S2 (plugins/soleur/test, Ref #9217)"
date: 2026-10-08
slug: grep-q-wave-b-s2-plugin-test-harness
branch: feat-one-shot-grep-q-wave-b-s2-drain-codemod
issue: 9217
lane: cross-domain
type: chore
priority: p3-low
domain: engineering
requires_cpo_signoff: false
brand_survival_threshold: aggregate pattern
---

# chore(ci): grep -q drain, Item B slice S2 (plugins/soleur/test, Ref #9217)

Spec lacks valid lane: no spec.md exists for this branch, so lane defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-08. **Gates run:** 4.6 user-brand impact (pass, `aggregate pattern`), 4.7 observability (pass; the `.test.sh` proxy hit on the suite-shaped-command condition is argued down with a measurement under the 15 s cap, plain and in a Check 10-shaped `bwrap`), 4.8 PAT-shaped variables (none), 4.9 UI wireframe (no UI surface), 4.10 encryption posture (no store or connection), 4.11 guard contract (`lint-guard-contract.py`: 1 entry; adequacy read: the Assembly names the chokepoint and the first-match-wins order, not today's members), 4.12 scope check (one live section, no BLOCKED marker, split assessment justified), 4.5 network-outage (no trigger pattern in the Overview or Problem Statement).
**Agents:** a learnings researcher and a functional-overlap check (no overlap) before drafting, an advisor consult, the plan-review panel (DHH, Kieran, code-simplicity), then test-design-reviewer, architecture-strategist and a standard-tier verify-the-negative sweep.

### Key improvements

1. Phase order fixed: the codemod refuses `apply --write` on a `=` row, so the row stays `<=` for the red step and the conversion and flips to `=` last (found by plan review; the first draft could not have run).
2. The advisor consult found that if the CI grep stops at the first match when stdout is `/dev/null`, every edit would be a no-op for the flake. Phase 0 now gates on a deterministic delayed-writer probe (measured: GNU grep 3.12 and 3.11 drain; `-q` gives 141, `-c >/dev/null` gives 0, no-match keeps rc 1).
3. The guard does not fail on slack for `<=` rows (measured), so the residual row becomes `=`; a banner label that only named the shape is reworded, taking the residual from 6 to 5 (135 edits, 567 test-shaped hits left).
4. Pair-run gate tightened (the 11 suites with a hand edit or reviewed-suspect conversion must read `identical`), the matrix gained a real-spelling row, and S3, S4 and S5 now wait for S2.

### New considerations

- Fifteen taste items are persisted in `decision-challenges.md` (row mode semantics, the unobservable `-m1` displays, matrix and pair-run size, the permanent probe row, the release-noise follow-up).
- The surviving mutant (move one of the five pins between files) is measured and listed, not claimed as covered.

## Overview

Slice S2 of Item B in the grep -q pipe-guard series (tracker #9217; also #7376, #6601, #7797, #9482). Slice S1 (PR #9720, merge `f44463a7e9`) landed the codemod `scripts/grep-q-drain-codemod.py` (modes `apply` and `verify`), its selftest inside `.claude/hooks/grep-q-pipe-guard.test.sh`, and the first conversions. Pass 1 (#9632) and Pass 2 (#9708) are on `origin/main` too. None of that is redone here.

S2 owns exactly one deferral row of the guard: `plugins/soleur/test/*` (140 lines in 48 files today). It converts the pipe-fed early-exit grep readers in that subtree from `producer | grep -q P` to `producer | grep -c ... >/dev/null P` (same exit status, reads to EOF, so the producer never takes SIGPIPE under `set -o pipefail`), proves the diff with `verify`, and lowers the row from 140 to its measured residual of 5, switching it from `<=` to `=` as the last edit so the guard itself can see a forgotten ceiling.

**Measured result of a full rehearsal on a scratch copy of `origin/main` `425ea0fc1f`** (nothing committed in this repository): 135 line edits in 46 files, of which 130 are codemod edits that `verify` accepts as a pure transform and 5 are hand edits; the row falls 140 to 5; the guard's other twelve rows are untouched; the test-shaped census falls 702 to 567.

**What fires on merge.** Re-derived over the 46 files against every `.github/workflows/*.yml` path filter: only `version-bump-and-release.yml` (push to main, `plugins/soleur/**`) matches, 46 of 46. That is a plugin patch release (a GitHub Release tag `v...`, no commit to main, no Docker image, no marketplace write). `web-platform-release.yml` excludes `plugins/soleur/test/**`, and `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml` match nothing, so `[skip-deploy-fix-apply]` is irrelevant and is not used.

**Honest scope.** All 46 files set `pipefail`, so the shape is live, but most of the 135 sites pipe a `printf`/`echo`/`cat` value of a few lines into `grep`, which only races when the writer is unfinished at the reader's exit. This PR pays the ledger down and removes a place where a new instance could hide in slack. It is not a flake fix and does not move any CI flake rate; the defect in this series that turned CI red is the producer-side form (S7).

## Research Reconciliation: brief and trackers vs measured reality

| Brief or tracker claim | Reality (command or file) | Plan response |
| --- | --- | --- |
| "find ... how slices S1..S7 were defined and which rows S2 owns; do not guess" | Defined in the S1 plan's Slice Register (`knowledge-base/project/plans/2026-10-07-fix-grep-q-wave-b-test-harness-and-producer-join-plan.md`, merged in `f44463a7e9`; the S2 definition is at its line 342 and the SWEEP_PROBE_CHECKS rule "Only S1 and S7 edit SWEEP_PROBE_CHECKS; S2 to S6 must leave it alone" at its line 354): one deferral row per PR, `S2 = plugins/soleur/test/*`. The tracker comments of 2026-10-08 12:07 and 13:39 only say "S2 to S7" and that the next slice is S2 and fires a plugin release | S2 owns that single row; S3 `scripts/*.test.sh`, S4 `tests/*`, S5 `plugins/soleur/*.test.sh` plus part of `apps/web-platform/*.test.sh`, S6 `apps/web-platform/infra/*.test.sh`, S7 the producer-side join and cleanup are later PRs |
| Brief lists thirteen DEFERRED rows (725 lines, WOULD-CHANGE 373 in 115 files) | `bash .claude/hooks/grep-q-pipe-guard.test.sh` on `origin/main` `425ea0fc1f` prints the same thirteen rows; the `apply` dry run is identical (PR #9653 landed meanwhile and added no hit) | S2's share: row `plugins/soleur/test/*` = H-m 2, T0 125, data 7, suspect 10 hits (144 hits on 140 lines), WOULD-CHANGE 122 lines in 38 files before the suspect files are read |
| S1 plan: "S2: 140 hits / 48 files; nine files overlap #8659" | 48 files own the row, 46 are edited; 11 of them are named in #8659 (list below) | Counts corrected here; the PR body lists the eleven |
| S1 plan: `worktree-manager-porcelain-sigpipe.test.sh` is a demonstration-suspect file | Confirmed: 4 hits in 2 data lines (perl mutation expressions), 1 live SIGPIPE demonstration (the stub-git reader), 1 banner label that names the shape | Two stay counted, the demonstration gets the `# sigpipe-demo: intentional` marker, the banner is reworded |
| Codemod rule R2: a file whose text names `sigpipe`, `EPIPE`, `false-FAIL` or `broken pipe` is never auto-applied | 10 hits in 8 files are held by that whole-file rule; 7 of the files only mention the words in a comment (table below) | `--reviewed-suspect` for the 7 files, justified in the PR body; the 8th is handled by hand |
| "the guard's slack is 0 on every DEFERRED line" (S1 plan) | Not enforced for `<=` rows. Measured: with 5 hits, ceiling `<= 6` rc 0, `= 6` rc 1 `FAIL: deferral ceiling is loose`. The header says it: "Shrink-only is a CONVENTION here, not enforced" | The residual row becomes `=` (last edit). Challengeable (decision-challenges item 1) |
| The codemod can convert any row | `apply --write` exits 2 on a row in mode `=` (it treats `=` as file-exact production carriers; `select_rows` in the tool and the selftest check `codemod-exact-row` pin it). Found by plan review | Sequencing: convert while the row is `<=`, flip to `=` as the last edit, run the idempotency dry run before the flip |
| `grep -c ... >/dev/null` drains the producer | GNU grep special-cases `/dev/null` stdout in some versions; a deterministic delayed-writer probe (below) on the dev host (GNU grep 3.12) and on `ubuntu:24.04` (GNU grep 3.11, the CI image family) prints `-q` 141 and `-c >/dev/null` 0 | Phase 0 re-runs the probe as a gate; BSD/macOS grep is not measured and is not a host this suite runs on |
| "plugin release fires" | `version-bump-and-release.yml` push filter is `plugins/soleur/**` with no `test/` exclusion; the trigger script matched 46 of 46 files and no other workflow | PR body first line says exactly that; labels `semver:patch`, `type/chore`, `domain/engineering` (verified to exist), no `app:web-platform` |
| S1 NOT-fixed: codemod edge cases found after the two-round cap | Two converted lines are leading-pipe continuations (`operator-ack-guard.test.sh`, `proc.test.sh`); in both the previous line ends in a backslash, not a group closer. The producer screen refused 0 lines in the row | Not fixed here (the tool is deleted in S7); `verify` is the check on those two lines |

## Research Insights

### Premise Validation

Checked 2026-10-08. Issues #9217, #7376, #6601, #7797, #9482, #9638, #9639, #8659, #7005 and #7432 are all OPEN. PR #9720 is MERGED (`f44463a7e9`) and an ancestor of `origin/main`. `origin/main` moved from `57cc8494d5` to `425ea0fc1f` (PR #9653, the destructive-command guard, three new suites under `plugins/soleur/test/`); the row count, the thirteen DEFERRED lines and the dry-run summary were re-measured on `425ea0fc1f` and are identical. The mechanism (a `grep -c ... >/dev/null` rewrite through a committed codemod) is in no rejected-alternatives table in `knowledge-base/engineering/architecture/decisions/` (ADR-119 uses the same rule as a design constraint). The idiom itself was probed (advisor consult): with a writer that emits a second line 0.4 s after the first, `grep -q` yields 141 and `grep -c 1 >/dev/null` yields 0 on GNU grep 3.12 (dev host) and 3.11 (`docker run ubuntu:24.04`), and 0 under dash. The open-PR intersection with the 46 files is empty (#9745, #9348 and #6778 touch other files).

### Property List and Cut List

Properties (each one observable):

- P1. Every pipe-fed early-exit reader under `plugins/soleur/test/` is exit-status-identical to its original and drains its producer, or is a named exception (five data pins, one live demonstration).
- P2. The row's ceiling equals the measured residual and the guard, not a reader, fails when it does not.
- P3. A reviewer can mechanically confirm that the diff is only the transform plus an enumerated hand queue (`verify`, `unexplained: 0`).
- P4. No converted suite changes its verdict (pair run, or a recorded reason it was not run).
- P5. The merge fires one named workflow, predicted before the PR and observed after.

Mechanisms the ask names and what each buys: the codemod dry run (P1, P3), the guard's `DEFERRED:` lines (P2), the evidence comment on #9217 (P5 and series accounting), the `ulimit` battery (mutation evidence for P2). Every one already exists on `origin/main`: the codemod and the guard are read, not extended.

**Cut List.**

| Cut | Buys | What already covers it |
| --- | --- | --- |
| A new `apply --exec-strings` mode for the one executed heredoc stub | converting executed strings mechanically | One hand edit listed to `verify` with a row that sees a changed loop condition; S1 deferred the mode "to a slice that has such sites", and one site does not justify a tool change (the tool is deleted in S7) |
| Fixing the codemod edge cases S1 listed | a more robust tool | The tool has one more run to make and is deleted in S7; `verify` is the check on the two continuation lines |
| A characterization row per converted site | rows that see a dropped `-x`, `-F` or `>/dev/null` | `verify` proves every other byte of a line unchanged; the S1 selftest holds one discrimination row per way the weaker form is satisfiable |
| A suite row for the two `grep -m1` display lines | observing the here-string rewrite | Both sit in a failure branch that only prints on a defect, so no row can reach them without breaking the suite on purpose. Evidence is one scratch run of old and new expression on a three-line input whose first match is on line 2 |
| File-exact residual rows with a `_ts_re` widening | closing add-one-delete-one for the five pins | Cut in S1; S7 revisits. The `=` mode closes only the forgotten-ceiling half |
| A permanent drain-probe row in the guard selftest (advisor suggestion) | the idiom stays proven on the CI grep | S2 may not edit `SWEEP_PROBE_CHECKS` (S1 plan); Phase 0 runs the probe as a gate and S7's plan decides whether to pin it (decision-challenges item 6) |
| Editing `scripts/lib/test-affected-paths.sh` or `scripts/test-all.sh` | hand-maintained edges | A changed test file selects itself; AC-5 reads `--print-selection` for the guard only |

### Census (guard-derived, 2026-10-08, `origin/main` `425ea0fc1f`)

Commands: `bash .claude/hooks/grep-q-pipe-guard.test.sh` (rc 0, under the 15 s cap at load average 9), then `python3 scripts/grep-q-drain-codemod.py apply --row 'plugins/soleur/test/*'` (dry run, rc 0).

| Quantity | Value |
| --- | --- |
| Row before | 140 lines (144 hits: a line can carry two), 48 files, ceiling 140, mode `<=` |
| Tiers (hits) | T0 125, H-m 2, data 7, suspect 10 |
| Producer screen | 0 refused as unbounded (`yes`, `tail -f`, `journalctl`, `docker logs`, `nc`, `while true`, `/dev/zero`, `timeout`, `sleep`) |
| Producer of the 135 edited lines (first token before the pipe) | mostly `printf`/`echo`/`cat` values (a crude first-token count, not a pinned command, gives 78 to 90 of 135); the rest commands, functions or filters (`grep` 9, `tr`, `sed`, `head`, `git`, `bash`, `python3`) |
| Files setting `pipefail` | 46 of 46 (explicit `set ... pipefail` line) |
| Suite wall time per side | 387 s for the 46 suites (sum of column 2 of `scripts/suite-durations.tsv`); the largest is `operator-ack-guard` at 109 s |

### Rehearsal (scratch copy of `origin/main`, no repository file touched)

`git archive origin/main` into the session scratch directory, one base commit, then: `apply --row 'plugins/soleur/test/*' --write` (122 lines, 38 files); a second `apply ... --write` with `--reviewed-suspect` for the seven files below (9 lines, 7 files); the five hand edits; the row set to `= | 5`. Results: `verify --base <base> --hand-edits <5 entries>` printed `verified: 130`, `hand-edited: 5`, `unexplained: 0` (the line with both a converted `-q` and a hand-edited `-m` counts as hand-edited); the guard printed `DEFERRED: plugins/soleur/test/* (5 hits, ceiling 5, mode =, slack 0, #9217)` rc 0; `git diff --numstat` showed 135 insertions and 135 deletions in 46 files. Run on the converted copy: `roadmap-reconcile.test.sh` 109 passed, `worktree-manager-porcelain-sigpipe.test.sh` all passed, `fixture-relative-assert` 62 (floor 62), `fixture-dir-operand-assert` 71 (floor 71), `fixture-cd-containment`, `git-fixture-containment` 25 of 25, and `lint-shell-capture-exit.py --baseline ...` 0 new, 224 baselined. The suites were not otherwise pair-run during planning (host contended, load average 9 to 13); that is Phase 3. The guard mutants of the Guard Contract matrix were run on this copy one at a time under `ulimit -v 6000000`.

### Suspect files read (R2 over-inclusion)

| File | Where it names the word | Verdict | Converted hits |
| --- | --- | --- | --- |
| `go-session-gates.test.sh` | header comment on the old unscoped absence grep and the early-match SIGPIPE | comment only | 1 |
| `issue-flow-measure.test.sh` | header rule "no `producer \| grep -q`" | comment only | 2 |
| `main-health-monitor-workflow.test.sh` | a python string that lints the workflow file for the banned shape | not a demonstration | 1 |
| `required-checks-canonical-parity.test.sh` | a comment on an early `head -1` close | comment only | 1 |
| `scripts-shard-runtime-coverage.test.sh` | two comments explaining why neighbouring lines already use here-strings | comment only | 2 |
| `ship-phase-7-poll-fixtures.test.sh` | a comment on a `head`-driven SIGPIPE demonstration; the converted hit is a different line inside a scenario function | not the demonstrated line | 1 |
| `sync-pr-behind.test.sh` | a comment on a display pipe's SIGPIPE | comment only | 1 |
| `worktree-manager-porcelain-sigpipe.test.sh` | the whole suite is the demonstration | by hand | 0 |

### Institutional learnings applied

- `knowledge-base/project/learnings/test-failures/2026-10-07-a-mechanical-rewrite-of-800-test-lines-needs-a-shell-aware-classifier-and-a-dry-run-that-names-what-it-refused.md`: classify before transform; the dry run names what it refused (this plan reads every refused line).
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-diff-verifier-cannot-use-the-hunk-as-its-unit-because-adjacent-changed-lines-merge.md`: `verify` keys hand edits by exact base-side range (the shared line 710).
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-ceiling-at-slack-zero-is-satisfied-by-moving-a-hit-between-two-files-and-a-file-exact-test-row-reads-as-production.md`: the add-one-delete-one hole; S2 adds the half the guard does not enforce at all (a ceiling above the hits).
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-behavior-preserving-grep-conversion-needs-rows-that-see-discrimination.md`: rows before the rewrite; a mutant table built from printed first-red rows.
- `knowledge-base/project/learnings/test-failures/2026-10-07-a-test-replica-of-production-logic-keeps-the-shape-the-carrier-just-dropped.md`: the carrier text pinned by `ship-phase-7-poll-fixtures.test.sh` lives in `.md` fences the sweep does not cover, so that pin stays data.
- `knowledge-base/project/learnings/workflow-issues/2026-10-02-early-exit-pipe-consumers-sigpipe-under-pipefail.md`: SIGPIPE shows only at real input scale, so a pair run on small fixtures proves "no verdict change", never "the race is gone"; the PR body says so.
- `knowledge-base/project/learnings/2026-10-05-a-guard-built-from-spellings-needed-an-allowlist-and-the-affected-run-saw-two-ratchets-my-targeted-tests-could-not.md`: targeted suites can be green while the affected ratchet group is red; AC-5 runs the ratchet lane.
- `knowledge-base/project/learnings/2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md`: a mutant counts as killed only on its named FAIL text with rc 1, never on any non-zero exit.

## Open Code-Review Overlap

88 open `code-review` issues were searched for the 46 files, the guard and the codemod (two-stage `gh issue list --json` then standalone `jq --arg`). One match:

- #8659 (33 test suites replace test-helpers' composed EXIT trap and leak the incident sandbox) names eleven of S2's files: `generate-kb-index`, `go-session-gates`, `lint-distribution-content`, `required-checks-canonical-parity`, `resolve-debt`, `ship-battery-owed`, `worktree-manager-atomic-config`, `worktree-manager-bare-in-dotgit-layout`, `worktree-manager-heal-stale-branch`, `worktree-manager-porcelain-sigpipe`, `worktree-manager-stale-lock-diag` (all `plugins/soleur/test/*.test.sh`). **Acknowledge**: trap ownership is untouched by a flag rewrite; the PR body lists the eleven so the two do not collide in review.

No overlap is folded in; none is deferred.

## Files to Edit

- `.claude/hooks/grep-q-pipe-guard.test.sh`: one table row, `'plugins/soleur/test/* | <= | 140 | #9217'` becomes `'plugins/soleur/test/* | = | 5 | #9217'`, with a two-line comment above it (five data pins, no pipes; `=` so a forgotten ceiling fails; the codemod refuses `--write` on `=` rows). Nothing else: not `SWEEP_PROBE_CHECKS`, not the header FORMS text, not any other row.
- 45 test files edited by the codemod (131 lines, one of them shared with a hand edit) plus `worktree-manager-porcelain-sigpipe.test.sh` (marker and banner), all under `plugins/soleur/test/`: `auto-close-scanner`, `check-red-on-main`, `ci-e2e-skip-anchors`, `ci-path-gating`, `claude-code-action-auth`, `generate-kb-index`, `git-tripwire`, `go-session-gates`, `hook-input-classification-mutation`, `issue-flow-measure`, `lane-frontmatter`, `lint-distribution-content`, `main-health-monitor-workflow`, `operator-9321-stages`, `operator-ack-guard`, `operator-agent-runnable`, `operator-digest-provision`, `operator-digest-skill`, `operator-digest-workflow`, `operator-stage-approval-hook`, `pr-fanout-ledger`, `preflight-check10-suite-integrity`, `proc`, `regenerate-shard-manifest`, `render-c4-model`, `required-checks-canonical-parity`, `required-checks-merge-group-coverage`, `resolve-debt`, `reusable-release-caller-permissions`, `roadmap-reconcile`, `scripts-shard-manifest`, `scripts-shard-runtime-coverage`, `scripts-shard-totality`, `ship-battery-owed`, `ship-phase-7-poll-fixtures`, `sync-pr-behind`, `terraform-drift-sentry-leg`, `unkept-promise-hook`, `vendor-drift-workflow`, `web-host-escrow-diagnose-workflow`, `workflow-run-deploy-invariants`, `worktree-manager-atomic-config`, `worktree-manager-bare-in-dotgit-layout`, `worktree-manager-heal-stale-branch`, `worktree-manager-porcelain-sigpipe`, `worktree-manager-stale-lock-diag` (each `*.test.sh`). Phase 0 re-derives the list from `apply`'s `CHANGED` output; this is the point-in-time expectation, not a pathspec.

Not touched, on purpose: `scripts/grep-q-drain-codemod.py` and the guard's selftest (S1; deleted in S7), `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh`, `plugins/soleur/skills/work/SKILL.md` (and every other `SKILL.md`: the three `.md` fences that carry the shape, in `ship`, `merge-pr` and `postmerge`, are Item F), `.mcp.json` of the main checkout, and `scripts/followthroughs/watchdog-debounce-soak-9686.sh` (pre-staged by someone else; stage by explicit path, never `git add -A`).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s2-drain-codemod/tasks.md`, `decision-challenges.md` and `hand-edits.txt` (the five-entry list `verify` consumes, base-side line numbers).
- One learning file under `knowledge-base/project/learnings/test-failures/` (candidate in AC-9). No new `*.test.sh`: a new suite would fall into the covered floor scope and need a `run_suite` registration in `scripts/test-all.sh`.

## Problem Statement

The guard defers 140 test-harness sites under `plugins/soleur/test/*` behind a `<=` ceiling that only a human lowers, and the guard does not even fail when the ceiling is left too high. The hand work is small and enumerable; the bulk is the mechanical transform S1 built a tool for.

## Proposed Solution

### The conversion form

Unchanged from S1: `<producer> | grep -q<flags> ARGS` becomes `<producer> | grep -c<flags> >/dev/null ARGS` (`q` replaced by `c`, the redirect inserted immediately after the flag cluster). For stdin-only operands (every converted site; with a FILE operand `grep -c` exits 2 on a missing file where `-q` can exit 0, which is out of contract) the exit status is identical to `grep -q` (0 iff a line was selected, `-v` and empty input included; S1 checked 1,080 rows under bash and dash), it reads the whole stream so the producer never takes EPIPE (re-probed in Phase 0), and it is valid in `/bin/sh`.

### Disposition of every hit that is not plain T0 (19 hits, re-read at file:line, base side)

| Site | Tier | Disposition | Observer |
| --- | --- | --- | --- |
| `deploy-arm-mutations.sh:73` | data | stays counted: a mutation row's replacement command (`{GT}` stands for `>`) | the suite's mutation table |
| `deploy-arm.test.sh:676` | data | stays: the pattern pins the text of the postmerge fence, `\| grep -qE '...deploy-arm\.sh'`, so it keeps the carrier's spelling | the suite's pin |
| `ship-phase-7-poll-fixtures.test.sh:209` | data | stays: one element of a token list pinned against the ship fence (`--help 2>/dev/null \| grep -q -- '--step'`) | the suite's pin |
| `worktree-manager-porcelain-sigpipe.test.sh:229`, `:236` | data | stay: perl substitutions that rewrite the script under test into the outlawed shape (the mutants) | the suite's A2 arm |
| `worktree-manager-porcelain-sigpipe.test.sh:369` | H-label | hand edit: the banner `echo "A6: no 'git worktree list … \| grep -q' pipeline remains in the script"` becomes `echo "A6: no piped grep -q over 'git worktree list' remains in the script"`. It is output text, nothing pins its spelling (a repo-wide `git grep` finds only itself), and the assertion below it carries its own label | A6's assertion is unchanged |
| `worktree-manager-porcelain-sigpipe.test.sh:288` | H-demo | marker `# sigpipe-demo: intentional` appended after `\|\| STUB_RC=$?`; the line asserts the stub git fails under an early-quitting reader (A0), converting it would remove the demonstration | A0 (asserts `STUB_RC` non-zero) |
| `roadmap-reconcile.test.sh:274` | H-exec | hand edit `grep -q 'roadmap-reconcile.sh'` to `grep -c 'roadmap-reconcile.sh' >/dev/null` inside the quoted-heredoc `FAKE` gh stub (executed, so not data; `<<'FAKE'` means no expansion) | TS15e (rc 143). Measured on the rehearsal copy: with `grep -vc` instead, TS15e reads `SIGTERM mid-fetch ends the run (expected [143] got [2])` |
| `git-tripwire.test.sh:124` | H-m | hand edit `printf '%s\n' "$msg" \| grep -m1 'unset' \| sed ...` to `grep -m1 'unset' <<<"$msg" \| sed ...` (no producer to signal) | none by construction (failure-branch display); scratch run |
| `web-host-escrow-diagnose-workflow.test.sh:710` | H-m (same line as a T0 hit) | the `-q` is converted by the codemod; the display `-m1` inside the `no ...` message becomes `grep -m1 $'\tFAIL$' <<<"$(printf '%s\n' "${BRES[@]}")" \| cut -f1`; the whole line is one hand-edit range | none by construction; scratch run |
| `go-session-gates.test.sh:439`, `issue-flow-measure.test.sh:196,242`, `main-health-monitor-workflow.test.sh:1379`, `required-checks-canonical-parity.test.sh:362`, `scripts-shard-runtime-coverage.test.sh:169,180`, `ship-phase-7-poll-fixtures.test.sh:2120`, `sync-pr-behind.test.sh:950` | suspect, read | converted with `--reviewed-suspect` for the seven files (table above) | each owning suite |

So S2 removes 135 lines of 140; five data lines remain and the row is `= | 5`.

### Ledger lowering

| Row | Before | After |
| --- | --- | --- |
| `plugins/soleur/test/*` | `<=` 140 | `=` 5 |
| the other twelve rows | unchanged | unchanged (`.claude/*.test.sh` 5, `tests/*` 181, `plugins/soleur/*.test.sh` 66, `apps/web-platform/*.test.sh` 180, `scripts/*.test.sh` 128, `scripts/test-*` 2, six production rows 23) |
| Test-shaped total (sum of the seven test rows) | 702 | 567 |

Row order is semantic ("first match wins"), and `plugins/soleur/*.test.sh` is a broader glob (`*` crosses `/`) that also matches `plugins/soleur/test/x.test.sh`, so the S2 row stays above it (mutant 5 below measures what happens otherwise).

### Phases

**Phase 0, re-measure and gate (read-only).** `git fetch origin main`; if `origin/main` is ahead of the branch, merge it once at the start (never mid-flight afterwards) and re-run everything below. (1) Gating probe, run on the dev host and on the CI image family: `bash -c 'set -o pipefail; (echo 1; sleep 0.4; echo 2) | grep -q 1; echo "q: $?"; (echo 1; sleep 0.4; echo 2) | grep -c 1 >/dev/null; echo "c: $?"; (echo 2; sleep 0.4; echo 3) | grep -c 1 >/dev/null; echo "nomatch: $?"'` and the same inside `docker run --rm ubuntu:24.04`. It must print `q: 141`, `c: 0` and `nomatch: 1` (no-match keeps rc 1; measured on the dev host); if `c` prints 141 stop, the S1 output shape is wrong for that grep. Exit-status identity itself (match, no match, `-v`, empty input) is carried by the S1 selftest rows, not re-proved here. (2) Run the guard and keep the `DEFERRED:` lines; run `apply --row 'plugins/soleur/test/*'` as a dry run and diff its QUEUE against the disposition table (any new queue entry stops the plan until read). (3) Re-run the trigger derivation over the `CHANGED` list (expect exactly `version-bump-and-release.yml`) and the open-PR intersection. (4) `uptime`: if the load average exceeds the core count, local `--affected` is skipped and the PR body says so verbatim.

**Phase 1, red first.** Edit only the guard row to `<= | 5` with its comment. The guard must go RED (`ceiling exceeded: plugins/soleur/test/* has 140 hits, ceiling 5`): that is the failing test the conversion has to satisfy (`cq-write-failing-tests-before`; the instrument is the existing guard, so there is no new test to write). The row stays `<=` because `apply --write` refuses a `=` row.

**Phase 2, convert.** Commit 1: `apply --row 'plugins/soleur/test/*' --write`, then the same with `--reviewed-suspect` for the seven files (122 + 9 lines). Commit 2: the five hand edits and `hand-edits.txt`. Stage by explicit path.

**Phase 3, verify, then flip.** `python3 scripts/grep-q-drain-codemod.py verify --base origin/main --hand-edits knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s2-drain-codemod/hand-edits.txt` prints `unexplained: 0`; the `apply --row ...` dry run prints `WOULD-CHANGE: 0 lines in 0 files`. Then flip the row to `= | 5` (last edit) and run the guard rc 0. `bash -n` on the 46 files. Pair run: a pristine copy of `origin/main` (`git archive` into a scratch directory, no worktree metadata) versus the branch, sequential, `ulimit -v 6000000`, `timeout 150` per suite and side, rc and result line compared; a timeout on both sides is `inconclusive`, never `identical`; a suite needing root, network or Doppler is `not run locally` with the reason. Then `bash scripts/pre-push-ratchet-lane.sh`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`, and `bash scripts/test-all.sh --affected` if the host allows.

**Phase 4, hand-applied mutation battery** (Guard Contract matrix) on scratch copies, one mutant at a time under `ulimit -v 6000000`, a green control first, the first red line recorded from printed output, restore check clean. Also the `roadmap-reconcile.test.sh` hand-edit row (swap `-c` for `-vc`, TS15e must go RED).

**Phase 5, evidence and ship.** One learning file; tracker comment on #9217 (before and after `DEFERRED:` table, the command behind each number, the NOT-fixed list); the ship tail. The PR body names which later work lowers this row next (Item F when the `.md` carrier fences convert, or S7), so an out-of-order merge reads as expected. Sequencing: S3, S4 and S5 are cut only after S2 has merged (their rows sit directly above and below the S2 row, so the two-line comment widens the conflict window; adjacent table lines conflict, the merge queue ejects rather than rebases, no mid-flight re-sync of a BEHIND branch).

## Alternative Approaches Considered

| Alternative | Why not |
| --- | --- |
| Keep the row `<=` at 5 (the S1 plan's "stay `<=`") | The guard does not fail on slack for `<=` (measured), so "lowered with no slack" would rest on a reader. `=` costs one character and no guard code |
| Set the row to `=` first (red-first on the final shape) | `apply --write` refuses a `=` row; the plan's own phase order would not run (found by plan review) |
| Split S2 into two PRs (file readers first, then values) | Both edit the same ceiling line and each fires its own plugin release; `verify` handles all 135 lines in one run |
| Convert the five data pins by rewording them | Each pin must keep the spelling of the thing it pins (a carrier fence, a mutation); rewording breaks the pin to satisfy a counter. The one banner that was only a label is reworded |
| Hand-convert the two `-m1` display lines with a suite row | Their branch only prints on a defect, so a row would have to break the suite on purpose; evidence is a scratch run |
| `--reviewed-suspect` for `worktree-manager-porcelain-sigpipe.test.sh` as well | It would convert the stub-git reader that the suite keeps as an early-quitting reader (A0), turning the arm vacuous |
| Fold S3 (`scripts/*.test.sh`, no workflow fires) into the same PR | One deferral row per PR is the series boundary; S3 touches `scripts/test-all.sh`, which degrades local `--affected` to the full battery |

## User-Brand Impact

- **If this lands broken, the user experiences:** a plugin test suite that stopped asserting what it names (a hook gate, a ship or postmerge fixture, a drift guard), so a regression in a policy-gate hook or in a release script ships green; the visible symptom is a defect the suite exists to catch reaching a released plugin build.
- **If this leaks, the user's workflow is exposed via:** no secret or user data is read or written by the change; the exposure vector is a fail-open conversion that makes a security-adjacent assertion pass vacuously (a dropped `-x` or `-F`, an inverted `!`, a hook-input fixture converted by mistake).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident` because no conversion touches user data, 130 of 135 edits are one-token rewrites proved by `verify`, and the five hand edits are enumerated and individually observed or evidenced; not `none` because a systematic classifier or transform error would repeat across the 46 suites, some of which guard hook policy, and the merge fires a plugin release, so the section carries no `threshold: none` scope-out.

## Observability

```yaml
liveness_signal:
  what: the grep-q-pipe-guard suite runs in the CI test group on every PR and merge_group run and prints PASS lines plus one DEFERRED line per row
  cadence: per PR and per merge_group run; run directly before each push
  alert_target: the required test check turns red on the PR, which blocks merge and ejects a queue entry
  configured_in: scripts/test-all.sh SUITE_GLOBS entry '.claude/hooks/*.test.sh' (registration), .claude/hooks/grep-q-pipe-guard.test.sh (the passes)
error_reporting:
  destination: CI job log of the test check (repo-hygiene guard, no Sentry surface)
  fail_loud: a FAIL line naming the row and the exceeded, loose or stale ceiling, or the file and line outside the table, exit 1; an unreadable input, an empty derived population or a missing python3 prints UNRESOLVED and exits 3
failure_modes:
  - mode: a new early-exit pipe lands under plugins/soleur/test
    detection: the row is tight (=), so hits above the ceiling report "ceiling exceeded"
    alert_route: required test check red on the PR
  - mode: the ceiling is left above the hits after a further conversion
    detection: mode = reports "ceiling is loose" (a <= row would pass silently)
    alert_route: required test check red on the PR
  - mode: a converted suite changes behavior
    detection: the suite's own result line compared base versus branch (recorded in the PR body) and the suite itself in CI
    alert_route: required test check red on the PR
  - mode: the plugin release run for the merge SHA fails or does not run
    detection: soleur:postmerge reads the version-bump-and-release run and the new release tag for the merge SHA
    alert_route: postmerge verdict on the PR; the workflow's own Slack notification
logs:
  where: CI job logs of the test check; locally the stdout of the guard
  retention: GitHub Actions log retention
discoverability_test:
  command: bash .claude/hooks/grep-q-pipe-guard.test.sh
  expected_output: grep-q-sweep-probe-pass
```

Detection note for preflight Check 10: one deterministic file, no build or network. The suite-shaped-command proxy (a `.test.sh` basename) fires on this command and is argued down by measurement: on 2026-10-08 the guard took 9.5 s at a host load average of 21 and 7.9 s inside a read-only `bwrap` with `env -i`, `PATH=/usr/local/bin:/usr/bin:/bin` and a tmpfs HOME (the Check 10 sandbox shape), rc 0 and `grep-q-sweep-probe-pass` printed both times, against the 15 s cap; the margin is thin on a contended host, so AC-9 re-measures it after the edit. The block is the same command S1 declared.

## Guard Contract

### Guard 1 — deferral row `plugins/soleur/test/*` after S2

**Property.** After S2, every pipe into an early-exit grep under `plugins/soleur/test/` is converted, marked as a demonstration, or one of the five counted pins, and the guard goes red both when a hit is added and when the ceiling is left above the hits.

**Assembly.** One population and one verdict: `scan_sweep <root>` (git grep over `SWEEP_PATHSPEC` with `PATTERN_V2`, comment and marker lines dropped) and `sweep_verdict` over `SWEEP_DEFERRALS`, plus the `_ts_re`/`GATED_PROD_ROWS` row-shape checks and the `DEFERRED:` print. The chokepoint is `scan_sweep`; the row is one line of one array whose order is semantic (first match wins), and the broader row `plugins/soleur/*.test.sh` also matches files under `plugins/soleur/test/`. The conversion tool (`apply`, `verify`) is a second reader of the same population, used as a parity check against the guard's sum before any edit, never as a second ledger.

**Mutation matrix** (hand-applied on a scratch copy of the converted tree, one mutant at a time under `ulimit -v 6000000`, green control first; every "measured" cell was printed during planning on the rehearsal copy at ceiling 5):

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `echo "$x" \| grep -q p` to a converted file under the row (`git-tripwire.test.sh`) | RED: `deferral ceiling exceeded: plugins/soleur/test/* has 6 hits, ceiling 5` (measured) |
| 2 | Revert one converted site (`grep -cx >/dev/null` back to `grep -qx`) in `worktree-manager-atomic-config.test.sh` | RED: same text, 6 hits (measured; proves tight against overshoot) |
| 3 | Set the ceiling to 6 with 5 hits (a lowering forgotten or off by one) | RED: `deferral ceiling is loose: plugins/soleur/test/* has 5 hits, ceiling 6 — lower the ceiling to 5` (measured). Control: the same edit in mode `<=` stays GREEN rc 0 (measured), which is why the row is `=` |
| 4 | Swap the S2 row and the `plugins/soleur/*.test.sh` row (deleting the S2 row reads the same: `plugins/soleur/*.test.sh has 70 hits, ceiling 66` plus `outside the deferral table (1 site(s))`) | RED: two FAIL lines, the broader row exceeded and the S2 row `loose ... has 1 hits, ceiling 5` (measured) |
| 5 | Empty the table (`SWEEP_DEFERRALS=()`), the guard's own dispatch | RED: `outside the deferral table (590 site(s))` and `the derived sweep's own probe is broken` (measured) |
| 6 | Append a hit to two different files after a compliant first (`git-tripwire.test.sh` and `proc.test.sh`) | RED: `has 7 hits, ceiling 5` (measured; a check that stops at the first member would read 6) |
| 7 | Append a hit in a spelling the converted lines used (`printf '%s\n' "$x" \| grep -qF -- "$x"`), so detection is tied to the real population and not to one canonical spelling | RED: `has 6 hits, ceiling 5` (measured) |
| 8 | Remove one data pin (`deploy-arm.test.sh`, spell `grep -[q]E`) and add a hit in another file | GREEN rc 0 (measured): add-one-delete-one, a known surviving mutant listed in Risks, not claimed as covered |

Harness rows. Suite edits that must go RED are mutants 1 and 3 (a ceiling one below and one above the hits). Must-PASS inputs that differ from the canonical in a way the contract permits: a hit line carrying a trailing `# sigpipe-demo: intentional` (not counted, ceiling stays 5, rc 0, measured) and a line `x \| grep -cE >/dev/null -- "$p"` (a spelling no converted line used, rc 0, measured).

Anchor. The ceiling and the checks live in the file they protect, so one commit can move both; this proves consistency, not integrity. What must also move for a weakening to pass: the PR body's before and after `DEFERRED:` lines (produced by the command and reviewable against the diff), the `verify` output, and the tracker comment on #9217. The add-one-delete-one hole stays open for the five pins until S7 decides on file-exact rows.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: an engineering-internal CI-hygiene change with no product, marketing, legal, finance, sales or support surface. The engineering lens (classifier safety, ledger design) is carried by the plan-review panel.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Plan ONLY Item B slice S2 now (own plan; it fires a plugin release; start with `python3 scripts/grep-q-drain-codemod.py apply` as a dry run and the guard's DEFERRED: lines)." [brief] | Overview, Census, Rehearsal, Phase 0 | mapped |
| 2 | "Pass 1, Pass 2 and Item B slice S1 (the S1 codemod PR, merged as commit f44463a7e9) are DONE; do not redo them." [brief] | Premise Validation, Overview, Files to Edit (not touched list) | mapped |
| 3 | "S3 to S7, Items D, E, F, G, I, H, the Wave A3 carriers and the #9639 and #9638 triage are LATER PRs in the same series, not this plan." [brief] | Research Reconciliation row 1, NOT-fixed list | mapped |
| 4 | "Per PR: evidence comment on the tracker (#9217), `Ref` not `Closes`, a plain NOT-fixed list, no [skip-deploy-fix-apply], nothing added to plugins/soleur/skills/work/SKILL.md." [brief] | Phase 5, AC-8, AC-9, AC-11 | mapped |
| 5 | "Run mutation batteries under `ulimit -v 6000000`, one mutant at a time." [brief] | Phase 4, Guard Contract, AC-6 | mapped |
| 6 | "Leave the main checkout's uncommitted .mcp.json alone and do not stage the pre-staged scripts/followthroughs/watchdog-debounce-soak-9686.sh." and "Do not edit /data/git-repositories/jikig-ai/soleur outside this worktree." [brief] | Files to Edit (not touched list), Phase 2, AC-9 | mapped |
| 7 | "Find in the tracker issue (gh issue view 9217 --comments) and the merged S1 commit f44463a7e9 how slices S1..S7 were defined and which rows S2 owns; do not guess the slice boundaries." [brief] | Research Reconciliation row 1 | mapped |
| 8 | "POPULATION 725 lines in 176 files; SUMMARY H-m=5 T0=388 X=1 data=127 suspect=214 unsure=20; WOULD-CHANGE 373 lines in 115 files." [brief] | Census (S2's share of that population) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Converting the 130 mechanical lines in 45 files with the S1 codemod | "start with `python3 scripts/grep-q-drain-codemod.py apply` as a dry run" | asked |
| Lowering the `plugins/soleur/test/*` ceiling in the guard | "which rows S2 owns" (ask 7) | asked |
| Evidence comment on #9217, `Ref`, NOT-fixed list, labels and PR-body first line about the release | "evidence comment on the tracker (#9217), `Ref` not `Closes`, a plain NOT-fixed list" | asked |
| Mutation battery and hand-edit row | "Run mutation batteries under `ulimit -v 6000000`, one mutant at a time." | asked |
| Row mode `=` for the residual row | — | inferred — justification: the guard header says shrink-only for `<=` is "a CONVENTION here, not enforced" (measured: `<= 6` over 5 hits passes), so the brief's "no slack" would otherwise rest on a reader; one character, no guard code |
| The five hand edits (two `-m1` displays, one executed heredoc stub, one marker, one banner label) | "start with ... the guard's DEFERRED: lines" | inferred — justification: each is a hit in the row the guard counts; leaving them would keep the ceiling above the five true data pins |
| `--reviewed-suspect` for seven files | "start with `python3 scripts/grep-q-drain-codemod.py apply` as a dry run" | inferred — justification: the codemod routes whole files naming sigpipe words to hand review; reading them is the only way to drain their 9 hits and the tool provides the flag for it |
| Phase 0 drain probe | — | inferred — justification: advisor consult; if the CI grep stops at the first match when stdout is `/dev/null`, all 135 edits are a no-op for the flake, and nothing else in the evidence plan could detect it |
| `hand-edits.txt`, `tasks.md`, `decision-challenges.md` | "Only files under knowledge-base/project/{plans,specs}/ may be modified." | inferred — justification: `verify` consumes the list, `soleur:work` consumes `tasks.md`, and the headless plan contract persists taste decisions for the ship PR body |
| One learning file | "a plain NOT-fixed list" | inferred — justification: the series convention is one learning per non-obvious finding; AC-9 names one candidate and forbids filler |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur`, `.claude`, `knowledge-base`
- Planned files: about 52 (46 test files, the guard, three spec files, one learning, the plan) | Estimated changed lines: about 180 (135 one-line edits, a 4-line guard edit, about 40 lines of documents)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the file count crosses the threshold only because the 46 test files are one-line edits proved by one `verify` run; the series boundary (one deferral row per PR) is already the split, and cutting the row in two would put two PRs on the same ceiling line and fire two plugin releases.

## Acceptance Criteria

Pre-merge boxes are checkable on the final tree; post-merge boxes are executed by `soleur:postmerge` and the tracker comment, with no human step.

### Pre-merge (PR)

- [ ] AC-1 `bash .claude/hooks/grep-q-pipe-guard.test.sh` rc 0 and its `DEFERRED:` lines read `plugins/soleur/test/* (5 hits, ceiling 5, mode =, slack 0, #9217)`, with the other twelve lines byte-identical to the merge-base's (`diff` of the two `DEFERRED:` sets is exactly that one line); the test-shaped total (sum of the seven test rows) is 567, down from 702, both sums pasted in the PR body. If Phase 0 finds different counts, the AC carries the re-measured numbers.
- [ ] AC-2 `python3 scripts/grep-q-drain-codemod.py verify --base origin/main --hand-edits knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s2-drain-codemod/hand-edits.txt` prints `verified: 130`, `hand-edited: 5`, `unexplained: 0` after `git fetch origin main` (the base SHA is named in the PR body); a further `apply --row 'plugins/soleur/test/*'` dry run, run before the flip to `=`, prints `WOULD-CHANGE: 0 lines in 0 files`; `bash -n` passes on all 46 edited files; `git diff --numstat origin/main...HEAD -- plugins/soleur/test/` shows insertions equal to deletions (135 each). `verify` proves the transform only; it does not prove a converted line was code rather than data (the classification is held by the data list read in this plan, the suspect-file read and AC-4).
- [ ] AC-3 The Phase 0 drain probe printed `q: 141`, `c: 0` and `nomatch: 1` on the dev host's grep and inside `ubuntu:24.04`, with both outputs in the PR body.
- [ ] AC-4 The PR body carries one table row per edited suite: identical rc and result line between the pristine copy and the branch, or `not run locally` with the reason, or `inconclusive` (timeout both sides). The 11 suites that carry a hand edit or a reviewed-suspect conversion (4 hand-edit files plus 7 suspect files) must read `identical`; `not run locally` and `inconclusive` are allowed only for the rest. CI's test group on the PR is the stated gate for P4; the table adds the before/after comparison CI cannot make. A difference blocks the PR until explained. The body states that a pair run on small fixtures shows "no verdict change", not "the race is gone".
- [ ] AC-5 `bash scripts/pre-push-ratchet-lane.sh`, `bash scripts/guard-vacuity-floor.test.sh`, `bash scripts/lint-orphan-test-suites.sh` and `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt` (0 new) pass; `bash scripts/test-all.sh --print-selection` on the branch diff prints `AFFECTED_SELECTED` 1 for the grep-q guard (a missing edge is named in the PR body, not fixed by editing `scripts/lib/test-affected-paths.sh`); `scripts/test-all.sh --affected` rc 0 or, if skipped, the sentence in AC-8.
- [ ] AC-6 The Guard 1 matrix (eight rows) was hand-applied on scratch copies after a green control, one mutant at a time under `ulimit -v 6000000`, each RED row killed by its named FAIL text with rc 1 (an rc 2, 126 or 127, or a crash, is an instrument failure and not a kill), mutant 8 recorded as the surviving one, the restore check clean (`git status` empty in the scratch copy).
- [ ] AC-7 The five hand edits carry their dispositions: `roadmap-reconcile.test.sh` TS15e goes RED when the converted line is swapped for `grep -vc` (named first-red line); the two `grep -m1` displays have one scratch run of old and new expression on a three-line input whose first match is on line 2, identical stdout, pasted in the PR body; the marker line leaves A0 asserting a non-zero `STUB_RC` and the guard no longer counts it; the reworded banner leaves A6's assertion unchanged.
- [ ] AC-8 The PR body (authored by `soleur:ship` from the diff plus `knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-s2-drain-codemod/`) has as its first line that merging fires one plugin release (`version-bump-and-release.yml`) and no web-platform release, apply or deploy, with the trigger derivation output over the 46 files (one workflow, 46 of 46); `Ref #9217` and never `Closes`; no `[skip-deploy-fix-apply]`; a `## Changelog` section; the NOT-fixed list under a heading that avoids the ship-gate deny tokens; the eleven #8659 files; labels `semver:patch`, `type/chore`, `domain/engineering` (no `app:web-platform`); and, if skipped, "`scripts/test-all.sh --affected` was not run because the host is contended (load average N), so CI is the gate."
- [ ] AC-9 Untouched, each checked against the merge-base: `git diff --stat origin/main...HEAD -- plugins/soleur/skills/work/SKILL.md scripts/grep-q-drain-codemod.py scripts/test-all.sh scripts/lib/test-affected-paths.sh` is empty; in the guard, `SWEEP_PROBE_CHECKS` and every row other than `plugins/soleur/test/*` are unchanged; no commit lists `scripts/followthroughs/watchdog-debounce-soak-9686.sh`; the main checkout's `.mcp.json` was not touched; no file outside this worktree and the session scratch directory was written. One learning file (candidate: a `<=` deferral row does not fail on slack, and the codemod refuses a `=` row, so the order is convert then flip), written only if still non-obvious at work time; `markdownlint-cli2` is clean on the plan, `tasks.md`, `decision-challenges.md` and the learning; the discoverability command is re-measured under the 15 s cap after the guard edit.

### Post-merge (automated)

- [ ] AC-10 Tracker comment on #9217 with the before and after `DEFERRED:` table, the per-tier counts, the command behind each number, and the NOT-fixed list; the `Filed:` line, Merge Danger (`Undo:` and `Blast Radius:`), Pipeline Tally, Changelog and Model Dissents sit in the PR body.
- [ ] AC-11 `soleur:postmerge`: `gh run list --workflow=version-bump-and-release.yml --json headSha,conclusion` shows a run for the merge SHA with conclusion success, and `gh release list --limit 3` shows a new `v` release (not `web-v`) targeting the merge SHA; no `web-platform-release`, `apply-web-platform-infra` or `apply-deploy-pipeline-fix` run exists for that SHA, recorded as such.

NOT fixed by S2 (stated in the PR body and the tracker comment): the other 562 test-shaped sites (S3 `scripts/*.test.sh` 128 and `scripts/test-*` 2, S4 `tests/*` 181, S5 `plugins/soleur/*.test.sh` 66 and `apps/web-platform/*.test.sh` partly, S6 the infra suites, five data lines in `.claude/*.test.sh`); the five data pins left in this row; the 23 wave A3 production sites; the producer-side join (S7); the guard's own blind spots (Item F: variable binary, flag order, wrappers such as `time`, `sh -c`, a subshell group or `rg`, split-line pipes, `| head`, the `.md` fences in `ship`, `merge-pr` and `postmerge` SKILL.md, `.ts`; the marker `# sigpipe-demo: intentional` being accepted with trailing text or inside a string and not being counted per row; no per-extension probe for `.bash`, `.bats` and `.yaml` in SWEEP_PATHSPEC); the codemod edge cases S1 listed; `verify`'s trust gaps; the add-one-delete-one hole in the five pins; #8659 trap ownership; #9638 and #9639.

## Test Scenarios

- Given the row at `<= | 5` before any edit, when the guard runs, then rc 1 `ceiling exceeded ... has 140 hits, ceiling 5` (Phase 1 red).
- Given the 135 edits applied and the row flipped to `= | 5`, when the guard runs, then rc 0 and the row prints `5 hits, ceiling 5, mode =, slack 0`.
- Given the row in mode `=`, when `apply --row 'plugins/soleur/test/*' --write` runs, then it exits 2 (the reason the flip is last).
- Given a writer that emits a second line after the first match, when it feeds `grep -c 1 >/dev/null` under `pipefail`, then the pipeline status is 0; with `grep -q 1` it is 141.
- Given a three-line message whose first `unset` is on line 2, when the old and the new `-m1` display expressions run, then both print the same single line.
- Given `worktree-manager-porcelain-sigpipe.test.sh` with the marker on the stub-git line, when the guard runs, then that line is not counted and A0 still sees the stub fail under an early-quitting reader.

## Risks and Sharp Edges

- **A classifier error converts data, and `verify` cannot see it** (a mis-converted data line still equals `transform(removed)`). Mitigations: the dry run's data list was read line by line above; the seven suspect files were read at file:line; the pair run; the owning suites. Hook-input fixtures are the worst case and none was found in this row (the data lines are mutation text and pins).
- **Known surviving mutant: add-one-delete-one** among the five pins (mutant 8). `=` closes the forgotten-ceiling half, not the swap. Listed, not claimed as covered; S7 revisits file-exact rows.
- **Mode `=` is overloaded.** The guard header describes it as "small and slow-moving" and the codemod reads it as file-exact production carriers; this row is a test glob in `=` mode, so no later slice can `apply --write` on it (S2 is the last one that needs to). The guard comment says so.
- **Row order.** `plugins/soleur/test/*` must stay above `plugins/soleur/*.test.sh` (mutant 4). A future slice that reorders the table by hand re-opens it.
- **A pinned carrier text.** `deploy-arm.test.sh` and `ship-phase-7-poll-fixtures.test.sh` pin the text of `.md` fences in `postmerge` and `ship`; when Item F converts those fences the pins move in lockstep or the suites go red.
- **Producers now run to EOF.** Wall time can rise where a producer is a full SUT run (`bash` and `python3` producers: 3 lines). The pair run records per-suite wall time and the body lists any suite that grows noticeably.
- **The marker is a comment.** `# sigpipe-demo: intentional` appended to a code line that ends in `|| STUB_RC=$?` must keep the statement intact; `bash -n` and the suite's A0 arm are the checks.
- **Merge trigger.** One plugin patch release. `semver:patch` and a `## Changelog` section follow the plugin's PR convention; `reusable-release.yml` defaults to patch with a warning when the label is absent, so the label is convention, not what makes the release patch-sized. A test-only change cutting a plugin release is noise that S5 (`plugins/soleur/*.test.sh`) will repeat; a `paths-ignore` for `plugins/soleur/test/**` on `version-bump-and-release.yml` is a workflow change outside this slice (decision-challenges item 10). Do not use `[skip-deploy-fix-apply]`.
- **The ledger table is a shared hot spot.** Merge S2 before cutting S3; resolve a one-line conflict by hand; never re-sync a BEHIND branch mid-flight; keep pushes minimal while the queue is saturated.
- **A failure message that quotes a command in backticks inside double quotes runs that command when the check fails** (S1 finding). Every battery runs under `ulimit -v 6000000`, and any new check text avoids backticks inside double quotes.
- **Verify the verifiers.** Every count in this plan was read from a command's output on `origin/main` `425ea0fc1f` or on the rehearsal copy; read rc files, not completion notifications, and do not start a second `git commit` while a hook is running.
- A plan whose `## User-Brand Impact` is empty, holds only `TBD`/`TODO`/placeholder text or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.

## Dependencies and References

- Tracker #9217 (this series); #7376, #6601 (related), #7005, #7432; #7797 (xtrace lint: comment only if a touched file enters its scope, which S2 does not); #9482 (only if a slice changes an ejection-class fact, expected in S7); #9638 and #9639 (not fixed).
- Merged: #9213, #9525, #9554, #9587, #9632, #9708, #9720 (S1, `f44463a7e9`).
- Guard: `.claude/hooks/grep-q-pipe-guard.test.sh` (header, `SWEEP_DEFERRALS`, `SWEEP_PROBE_CHECKS`, `GATED_PROD_ROWS`, `_ts_re`). Tool: `scripts/grep-q-drain-codemod.py`.
- Series plan: `knowledge-base/project/plans/2026-10-07-fix-grep-q-wave-b-test-harness-and-producer-join-plan.md` (Slice Register, Producer-side join design) and its `knowledge-base/project/specs/feat-one-shot-grep-q-wave-b-test-harness/decision-challenges.md`.
- Workflow read for the trigger: `.github/workflows/version-bump-and-release.yml` (and `reusable-release.yml` for the semver label); `plugins/soleur/AGENTS.md` for the release mechanics.
