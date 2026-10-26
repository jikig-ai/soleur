---
title: "ci: S4 PR5 measurement slice, per-suite duration and 200-PR selection replay for the whole-tree readers"
date: 2026-10-26
slug: ci-s4-affected-index-pr5-glob-measurements
branch: feat-one-shot-s4-pr5-glob-measurements
issue: 10861
type: chore
lane: cross-domain
refs: [10861, 10448, 9729]
brand_survival_threshold: aggregate pattern
---

# ci: S4 PR5 measurement slice, per-suite duration and 200-PR selection replay for the whole-tree readers

Ref #10861 (PR5 tracker, stays open: this PR is its measurement slice, not the close-out). Ref #10448 (series tracker). Ref #9729 (epic). PR text uses `Ref` only, never a closing keyword.
Draft PR #11226 (branch `feat-one-shot-s4-pr5-glob-measurements`) already exists. It carries no `s4-drain` label yet; the claim is made in Phase 3 only if an index edit is going to happen (no open PR holds the label at plan time).
Spec lacks a valid `lane:` (there is no spec.md for this branch), so it defaults to `cross-domain` (fail-closed).

## Overview

PR4c ended the drain series and handed PR5 the whole-tree readers: 43 (suite, path) pairs that a `glob:` edge or an `ALWAYS_ON_SUITES` entry must express, because no exact-file list can. CTO row 6 of PR4b (2026-10-25) ruled the policy and CTO row 7 of PR4c (2026-10-26) ruled that PR5 executes it with two measurements taken fresh, at work time, on current `origin/main`, with a stop line: no pair is globbed or added to `ALWAYS_ON_SUITES` unless both measurements were taken in this PR and meet the thresholds.

This PR does five things:

1. **Builds the missing measurement.** The replay tool has no per-glob selection rate (its `collect` stores only the skipped-suite list per commit and needs GitHub run reads). A read-only `glob-rate` subcommand is added to `scripts/ci-pr-affected-replay.py` and tested first.
2. **Takes measurement 1 (duration)** of the four suites from `scripts/suite-durations.tsv` (and `-heavy.tsv`), recording the `src` column, at the work-time `origin/main` SHA.
3. **Takes measurement 2 (the 200-PR selection replay)** per candidate glob set over the last 200 first-parent commits of `origin/main`, at the same SHA, with the model spot-checked against the real selector.
4. **Applies row 6 as written** through a verdict encoded in the tool (`glob`, `always_on`, `baselined`), including the `boundary-prefix` decision. Only a suite whose verdict is `glob` or `always_on` gets an index edit; everything else stays baselined and is listed for an explicit call on #10861.
5. **Records what remains** for the rest of #10861. The baseline file is NOT deleted and no ADR-276 closing line is appended (strict zero is unreachable under the holds).

Holds that stay in force: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run (`collect`, `ejections`, `aggregate`, `verdict` are not run), no flip PR.

The measured set is **four suites**, not 43: the brief's "43 whole-tree/glob-read suites" are 43 pairs over three suites (`.claude/hooks/grep-q-pipe-guard.test.sh` 22, label `plugins/soleur` 16, `tests/scripts/argv-bearer-sweep` 5, counted from `receipts/handoff-pr5-deferred-sweep.tsv`), plus `plugins/soleur/test/boundary-prefix.test.sh` (section 1 of `handoff-pr5-notes.md`). Verdicts are per suite; the pairs follow their suite.

## Research Insights

### Premise validation (Phase 0.6)

Checked live on 2026-10-26: #10861 OPEN (title "ci: S4 PR5, accept rows and non-code pairs, delete the baseline (strict zero)"); #10959, #10859, #10414, #10448 OPEN; PR #11226 OPEN and draft, no label; no open PR carries `s4-drain`. The handoff receipts exist under `knowledge-base/project/specs/archive/20261026-120221-feat-one-shot-s4-affected-index-pr4c-held-back-edges/receipts/` (`handoff-pr5-notes.md`, `handoff-pr5-deferred-sweep.tsv`, `edges-decisions.tsv`). `scripts/suite-durations.tsv`, `scripts/suite-durations-heavy.tsv` and `scripts/ci-pr-affected-replay.py` exist on `origin/main`. Stale premises found:

- "43 whole-tree/glob-read suites" is 43 pairs over three suites (above).
- "per-suite duration from `scripts/suite-durations.tsv`" cannot be taken for two of the four: label `plugins/soleur` has no row in either duration table, and `plugins/soleur/test/boundary-prefix.test.sh` is `src=floor` (an estimate, not a timing). Ruled in decision-challenges row 3.
- "the replay tool may already compute it": it does not (see the Cut List).
- The ADR corpus was grepped for the mechanism (`glob:` edge, `ALWAYS_ON_SUITES`, row 6): ADR-242 decision 22 created the `glob:` kind, ADR-276 item 3 and its PR3a amendment assign "the rest" to PR5; neither rejects a glob or an always-on entry for a whole-tree reader. The mechanism is the ruled policy, not an unconsidered idea.

### Property List and Cut List (Phase 0.6b)

Properties the ask needs:

- P1. For each of the four suites, a duration figure whose provenance (`measured`, `floor`, missing) is visible next to the verdict.
- P2. For each candidate glob set, a selection rate over the last 200 merged PRs taken at work time on the recorded `origin/main` SHA, that includes what the suite already selects today.
- P3. A verdict per suite that applies the three row 6 branches exactly (inclusive boundaries) and cannot return `glob` or `always_on` on a floor, missing or disagreeing measurement.
- P4. An index edit only where the verdict allows it, with the baseline pruned (shrink-only) and the now-stale accept rows removed.
- P5. A list of what stays baselined, with the reason, for the explicit call.

Mechanisms the ask proposes, and what already buys the property:

| Mechanism in the ask | Property | Already on `origin/main`? | Result |
|---|---|---|---|
| "build the replay measurement if the tool cannot compute a per-glob selection rate" | P2 | Grepped the authority, `scripts/ci-pr-affected-replay.py` (`cmd_collect`, `fill_selection`, `select`, `edge_hit`, `commit_files`, `durations`): `collect` stores `skipped_suites` and a minute total per commit, never the selected set, and needs `gh` run reads; no subcommand computes a rate for a hypothetical edge. `edge_hit` (Python mirror of the bash match, differential-tested) and `commit_files` are the reusable parts. | Build `glob-rate` on those two primitives. Not a new script: a new suite would need a `run_suite` registration plus shard-legs, durations and classification plumbing. |
| Run the real selector once per merged PR | P2 | `bash scripts/test-all.sh --print-selection --paths=...` prints, per suite, the bit AND the full edge set (column 5). A real run cost minutes cold and tens of seconds warm at plan time, so 200 runs is hours. | Cut. Run the selector ONCE for the edge sets and evaluate the 200 diffs with `edge_hit`; spot-check K diffs against the real selector (CTO row 6). |
| Per-suite duration from the tsv | P1 | `scripts/suite-durations.tsv` carries `src=measured|floor`. | Reuse; add a reader that keeps the `src` column (`durations()` drops it and must stay untouched, the evidence path uses it). |
| A new verdict script | P3 | none | Cut as a separate script; the verdict is one function inside `glob-rate` (CTO row 7). |

### Value-proposition measurement (Phase 0.6c)

The saving this PR can claim is baseline pairs drained without a hold and without an accept row, set against CI minutes added when the lever flips. Both sides are produced by one command at work time, not asserted now: `python3 -I scripts/ci-pr-affected-replay.py glob-rate ...` prints, per suite, `ci_seconds_added = duration_s x (total_hits - existing_hits)` over the 200 units, and the baseline line count before and after (`wc -l scripts/ci-pr-affected-audit.baseline.tsv`, `git show origin/main:...`) gives the drained pairs. At plan time neither number exists, and the plan stores none.

### Institutional learnings applied

- `2026-10-09-committed-ci-weights-are-not-local-costs.md`: a `src=floor` row is a claim, not a measurement; a threshold over floor-priced rows is vacuous; gate on measured rows only and make a missing row red. Encoded in the verdict (floor or missing is always `baselined`).
- `2026-10-03-a-manifest-priced-from-staged-runs-misses-a-suite-that-landed-after-them.md`: re-read the inputs at the moment of measurement; the tool stamps the `origin/main` SHA and the date on every output.
- `2026-10-09-a-cost-lever-must-not-be-able-to-redden-the-run-it-saves.md`: every threshold branch needs its own red and green fixture plus a mutant that deletes it (the boundary rows and the Guard Contract below).
- `2026-09-30-print-affected-set-prints-classes-not-selection-and-the-ask-was-half-shipped.md`: measure selection from the pre-pass bits (`--print-selection`), never from a classification receipt (`--print-affected-set`); re-derive any count with a command before quoting it.
- `2026-10-01-the-pre-pass-cost-was-first-touch-attribution-and-a-bash-52-option-not-the-suites-the-issue-named.md`: never edit a script a long selector run is reading; the edge-set run finishes before any index edit (Phase order).
- `2026-10-25-draining-an-index-by-declaring-edges-reveals-pairs-and-per-batch-commits-do-not-survive-a-moving-main.md`: regenerate the baseline only with `ratchet --print-baseline`; check `uniq -d` on `AFFECTED_*_PATHS`; the stop line is decided before declaring.
- `2026-10-25-a-read-recorder-classifies-revealed-pairs-and-an-all-edges-trial-sizes-a-drain.md`: the recorder is evidence; a suite that does not record cleanly (rc != 0, bulk reader) is counted, not dropped; `sort -c` the accept file.
- `2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md`: run the ratchet on the merged tree after every sibling merge.
- `2026-10-22-a-hop-regex-was-quadratic-on-one-long-token-and-my-own-stale-runs-held-the-test-queue.md`: any new matching over repo text gets a one-long-token cost row (the new code reuses `edge_hit`, whose glob arm is linear; the row pins that for the candidate entries).
- `2026-10-19-the-audit-a-ratchet-trusts-reached-less-than-its-name-and-both-p1s-were-in-the-fixes.md`: state the reach of a new subcommand and pin fix commits with an independent instrument (the real-selector spot-check is that instrument).

## Research Reconciliation: Spec vs. Codebase

| Brief or handoff claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "the 43 whole-tree/glob-read suites" | 43 pairs over three suites; `boundary-prefix` is a fourth reader outside the 43 | Measure four suites; verdicts per suite (Overview) |
| "per-suite duration from scripts/suite-durations.tsv" | `plugins/soleur` has no row; `boundary-prefix` is `src=floor`; the other two are `measured` | Phase 2.2 and CTO rows 3 and T1: floor or missing never yields a verdict other than `baselined` (`duration-floor`, `duration-missing`); a gated-out suite gets no candidate set |
| "the replay tool may compute a per-glob selection rate" | It does not (Cut List) | Build `glob-rate` (Phase 1) |
| "200 merged PRs" | The last 200 first-parent commits of `origin/main`; at plan time every one had a `(#N)` subject (32 of them merge commits), so one commit is one merged PR | Phase 2.1 re-verifies the count, the `(#N)` subjects and the distinct PR numbers at work time |
| "a `glob:` decision for `boundary-prefix` covers the held `guardrails.sh` edge" | The suite has exactly one baselined pair left (`.claude/hooks/guardrails.sh`); PR4c declared the other hook and library files as exact entries | Candidate set from the suite's four scan globs (Phase 2.4); a glob never reveals pairs (glob and directory entries are read by no audit pass) |
| "PR5 deletes the baseline and appends the ADR-276 closing line" (issue body) | Strict zero is unreachable under the holds: 31 `grep-q-pipe-guard` edges, `git-data-birth-readiness-gate` (151 pairs), the bulk readers and the non-code pairs remain | CTO row 8: neither the deletion nor the closing line is in this slice; the remainder is reported on #10861 |

## Technical Rulings (CTO agent, 2026-10-26; full text in `knowledge-base/project/specs/feat-one-shot-s4-pr5-glob-measurements/decision-challenges.md`, rows 1-12)

1. **Rate** that decides row 6 is the TOTAL selection after the edge (existing edges OR the candidate glob); glob-only and incremental are printed beside it.
2. **Denominator** is fixed at 200; runner-changed fallback, always_on, not-evaluable and empty-diff units count as selected; the excluded reading is printed too; a verdict needs both readings to agree, else `baselined`.
3. **Duration gaps**: `floor` and missing rows are not measurements and give `baselined` (`duration-floor`, `duration-missing`); a local timing can never change a verdict because this machine is not the CI runner class, so the `src=direct` machinery is cut (round 2, T1) and a local figure may appear only as one informational line in the #10861 comment.
4. **Candidate sets** come from the suite's scan scope plus recorder evidence, cover the suite's rows of the 43-pair scope (plus the one `boundary-prefix` pair), and a per-extension per-top-level-directory set needs every directory with a tracked file of those extensions to have an entry; otherwise the suite is judged `always_on`-or-`baselined` only.
5. **Hot-file budget does not apply to a `glob:` edge.** The budget governs exact-file edges that reveal pairs; row 6 governs globs, and a hot file's churn already shows in the replayed rate.
6. **Tool placement**: read-only `glob-rate` subcommand in `scripts/ci-pr-affected-replay.py`, tests in the registered `plugins/soleur/test/ci-pr-affected-replay.test.sh`, spot-check against the real selector; a disagreement stops the work.
7. **Verdict encoded** with inclusive boundaries (<= 60000 ms and <= 50 of 200 for `glob`; <= 30000 ms for `always_on`), unit tests at 50/51, 60000/60001, 30000/30001, always `baselined` on floor, missing or disagreeing readings; output stamps SHA and date.
8. **Baseline and scope**: prune with `ratchet --print-baseline`; delete accept rows of any suite that becomes ALWAYS_ON; do not delete the baseline, do not append the ADR-276 closing line; editing the index degrades the local gate to the full battery once (noted in the PR body).

Round 2 (after plan-review, rows 9-12): the `src=direct` machinery is cut (a local timing cannot change a verdict); the test and mutation set is trimmed to one row per ruling; the runbook gets a one-clause PR5 exception on the Breadth and "Never in a drain PR" bullets; the `s4-drain` label, the #10448 mirror comment and the #10865 merge-SHA comment are all kept, conditional on an index or baseline edit.

The policy these rulings execute (PR4b row 6, verbatim): "per whole-tree or glob reader: (1) a `glob:` edge if the suite's duration in `scripts/suite-durations.tsv` is 60 s or less and a replay over the last 200 merged PRs selects it in at most 25% of them; (2) `ALWAYS_ON_SUITES` if the glob selects it more often and the suite takes 30 s or less; (3) otherwise the pair stays baselined until a PR5 decision. Accept-with-reason is NEVER used for a real whole-tree reader, only for mentions. The later PR must bring two measurements: per-suite duration from `suite-durations.tsv` and the 200-PR selection-size replay per glob." The stop line (PR4c row 7): no pair is globbed or added to `ALWAYS_ON_SUITES` unless both measurements were taken in this PR and meet the row 6 thresholds; otherwise it stays baselined and is listed for an explicit call.

## Implementation Phases

Process rules. Work in the worktree only; never `git stash`. Do not edit `scripts/lib/test-affected-paths.sh` or `scripts/test-all.sh` while a selector run is reading them. Every number in a receipt is produced by a command in this plan at work time; no number from an earlier PR or from this planning session is copied. Long commands (the selector, the recorder, the replay suite) run with `run_in_background` and are awaited with Monitor-style until-loops, never `sleep`.

### Phase 0 - base and preflight (no repo edit)

- 0.1 `git fetch origin main`; merge `origin/main` into the branch; record `BASE=$(git rev-parse origin/main)` and `date -u` in `receipts/measurement-stamp.txt`. Every later command that says "current origin/main" uses `BASE`; if `origin/main` moves before the push, re-run Phases 2 and 3 on the new SHA (the receipts must name the SHA the PR is based on).
- 0.2 Re-verify the premises that gate the work: `gh issue view 10861 --json state`, `gh pr list --label s4-drain --state open` (must be empty before Phase 3), the holds untouched (`gh issue view 10414 10859 --json state`), the handoff receipts present.
- 0.2b Re-grep the two consumer lines quoted under "Consumer of the declared lists" and the four array names (`grep -n 'AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS=' scripts/lib/test-affected-paths.sh` and its three siblings); a rename moves the plan.
- 0.3 Take the edge sets once, before any edit: `bash scripts/test-all.sh --print-selection --paths=README.md > receipts/rows.txt` (background; cold run takes minutes). It is the "existing edges" input of measurement 2. Check the last line is `AFFECTED_SUMMARY ... fallback=none` and the four labels have rows (`.claude/hooks/grep-q-pipe-guard.test.sh`, `plugins/soleur`, `tests/scripts/argv-bearer-sweep`, `plugins/soleur/test/boundary-prefix.test.sh`).

### Phase 1 - build the measurement first (tests before code)

- 1.1 **Failing tests first** in `plugins/soleur/test/ci-pr-affected-replay.test.sh`, a new section `== glob-rate (S4 PR5)`, using the file's existing seams (synthesized git repo with an `origin/main` ref, `PR_AFFECTED_REPLAY_TEST_ALL` stub selector that prints `AFFECTED_SELECTED` rows with an edge column, mutation harness that copies the SUT and applies one edit). One row per ruling, no more:
  - glob-only, existing-only, total and incremental counts on a 6-commit fixture where each commit is crafted to hit one, both or neither; a suite with an empty candidate field is still listed (existing-only);
  - an `always_on` row counts selected on every unit; a diff touching `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh` is a `runner-changed` unit; a path with a comma, a non-printable byte and an empty diff are not-evaluable; all four count as selected in the conservative reading and are excluded in the other, and the output prints their counts;
  - one table-driven verdict row: duration 60000 vs 60001, 30000 vs 30001, rate 50 vs 51 of 200 (the bar is a ratio, `hits * 4 <= units`, also checked at another N);
  - `src=floor`, a missing row, and two readings that disagree each give `baselined` with reason codes `duration-floor`, `duration-missing`, `readings-disagree`;
  - candidate coverage: a candidate set that misses a baselined pair of its suite is refused (rc 2) for a `glob` verdict; the directory-completeness check against `git ls-files` flags a directory with a tracked file of a covered extension and no entry, includes a root-level file fixture, and is cross-checked by a second enumerator (`git ls-files | grep -E '\.ext$' | wc -l` equals the per-directory sum); a malformed entry is refused;
  - a candidates file with comments, blank lines, CRLF, shuffled order and an extra suite gives the same verdicts as the canonical file (must-PASS non-canonical input);
  - the spot-check: model and stub-real selector agree on the sampled diffs; a stub that disagrees on one suite stops the run with rc 4 naming the suite and the diff. The long-token and malformed-glob semantics of `edge_hit` are already pinned by its differential rows and are not repeated (CTO round 2, T2).
- 1.2 Implement `cmd_glob_rate` (read-only: writes only under `--out`; the selector subprocess keeps `select_env` and its own derive cache). Signature: `glob-rate --candidates FILE --out DIR [--list FILE] [--commits 200] [--base REF] [--pairs FILE] [--spot-check K]`.
  - `--candidates`: `suite<TAB>entry` lines (a blank entry lists the suite with no candidate), entries spelled as in the index arrays (`glob:head/**.ext`, `dir/`, exact file); the tool classifies each entry with the same rules `edge_hit` applies and refuses a malformed one (it would always match and inflate the rate). `--pairs` is the set of pairs a `glob` verdict must cover (see 2.5), as `suite<TAB>path` lines.
  - `--list`: the saved `receipts/rows.txt`; without it the tool runs the selector once (`--paths=README.md`) as `load_rows` does. `--base` takes the recorded SHA, not a moving ref.
  - Per first-parent commit: `commit_files`, `evaluable`, the runner-changed test, then per suite `existing_hit` (always_on, or any row edge hits any file), `glob_hit` (any candidate entry hits any file) and `total = existing OR glob`.
  - Durations: a new `durations_src(root)` reading `(ms, src)` from both tables (the existing `durations()` stays byte-identical, the escape-rate path uses it). No `src=direct` input exists (CTO round 2, T1).
  - Output under `--out`: `glob-rate.tsv` is the stop-line table (suite, entry count, duration_ms, src, existing_hits, glob_hits, total_hits, incremental_hits, units, runner_changed, not_evaluable, empty, rate_conservative, rate_excluded, ci_seconds_added, drained_pairs, verdict, reason) and carries no date or clock value, so a re-run on the same SHA is byte-identical; one marker line `SOLEUR_PR_AFFECTED_GLOB_RATE base=<sha12> date=<utc> units=<n> ...` carries the date. `ci_seconds_added = duration_s x (total_hits - existing_hits)` for a `glob` verdict and `duration_s x (units - existing_hits)` for `always_on`. Exit 0 all rows decided, 2 usage or refused input, 3 a read failed, 4 spot-check divergence or an internal error.
  - `--spot-check K` picks K evaluable non-runner units at evenly spaced indexes (no randomness, so the run is reproducible) and compares `existing_hit` of every suite with the real selector's bit for that diff. The run exits 4 unless exactly K units were sampled and K > 0 (an empty sample must not pass). It cannot see the glob half of the model, which the real selector does not have yet; that half is checked in 2.7.
  - Update the top-level docstring SUBCOMMANDS list and `--help` with the reach: the model decides selection from the selector's own edge column plus `edge_hit`; it does not model a fallback other than runner-changed, and it evaluates the CURRENT index against OLDER diffs (the replay's standing limit). It uses `--paths`, which skips the registration-only classifier, so a runner-trigger diff that the real gate would bound is still counted runner-changed (conservative).
- 1.3 Run the new section to green, then the whole replay suite detached (`bash plugins/soleur/test/ci-pr-affected-replay.test.sh`), shellcheck on the test file, `python3 -I -m py_compile scripts/ci-pr-affected-replay.py`. Commit (tool plus tests) before any measurement so the receipts name a committed tool.

### Phase 2 - take both measurements (work time, current `origin/main`)

- 2.1 **The 200 units.** `git rev-list --first-parent -n 200 $BASE --format=%s`: assert 200 commits, every subject ends `(#N)`, print the number of distinct PR numbers and the oldest and newest commit dates into `receipts/measurement-stamp.txt`. A subject without `(#N)` is a unit that is not a merged PR: replace it by walking further back and state the replacement.
- 2.2 **Measurement 1, duration, and the duration gate.** For the four labels: `awk -F'\t' -v l="$LABEL" '$1==l' scripts/suite-durations.tsv scripts/suite-durations-heavy.tsv`, saved with the `src` column to `receipts/durations.tsv` (a label with no row is written as `missing`). A `floor` row is an estimate, not a timing, and a missing row is no figure: both give `baselined` with reason `duration-floor` or `duration-missing` (CTO rows 3 and T1; no local timing can change a verdict, because this machine is not the CI runner class that produced the `measured` rows). A `measured` row over 60000 ms gives `duration-over`. Only suites that pass the gate (`measured`, at most 60000 ms) continue to 2.3-2.7; a gated-out suite keeps an existing-only row in the tool output (empty candidate field) so the rate under today's edges is still reported. If a local timing helps the explicit call, one line in the #10861 comment labelled "local, not CI class, informational" is enough. Do NOT run `scripts/regenerate-shard-manifest.py` (it rewrites committed duration and shard tables, out of scope).
- 2.3 **Recorder evidence for the candidate sets** (evidence, never a gate), gate-passing suites only: one attempt per label, no retry loop, `bash scripts/audit-suite-reads.sh record --mode check --only <label> --cover-from-selection --out receipts/retest/`; a label that records `unreliable` or exits non-zero (bulk reader, a whole `bun test`) is listed with that reason and its candidate set comes from the suite text alone, said so in the receipt.
- 2.4 **Candidate sets** (`receipts/candidates.tsv`), gate-passing suites only, derived from each suite's scan scope, each entry checked with `git ls-files | grep -E '<translation>'` to match at least one tracked file:
  - `.claude/hooks/grep-q-pipe-guard.test.sh`: scan scope is `.claude/hooks/*.sh` and `.claude/hooks/lib/*.sh` (the `git grep` pathspecs) plus every tracked file of the extensions in `SWEEP_EXTS` and `PJ_EXTS` (the join and sweep walks). A root-anchored `glob:` entry matches only dir-less paths, so the set is one `glob:<top-level-dir>/**.<ext>` entry per top-level directory and extension plus the dir-less root forms; the tool's directory-completeness check proves no directory with a tracked file of those extensions is missed. If a complete set is not expressible, the suite is judged `always_on`-or-`baselined` only (CTO row 4).
  - `plugins/soleur` (`bun test plugins/soleur/`): no duration row, so it stops at the gate (`duration-missing`); its candidate set is not built.
  - `tests/scripts/argv-bearer-sweep`: scope from the suite's header (derived population `scripts/followthroughs/*.sh`, S3 stage over workflow and composite-action texts) plus the recorder; the existing `scripts/followthroughs/` directory edge stays.
  - `plugins/soleur/test/boundary-prefix.test.sh`: `src=floor`, so it stops at the gate (`duration-floor`); the four scan globs of `boundary-prefix.test.sh:285-299` are recorded as the intended expression (`glob:.claude/hooks/**.sh`, `glob:plugins/soleur/scripts/**.sh`, with the excess-file count the tool prints for the explicit call). The hot-file budget does not apply to this decision (ruling 5): the row 6 measurement does.
- 2.5 **Pair coverage scope.** A `glob` verdict must cover the suite's rows of `handoff-pr5-deferred-sweep.tsv` (the 43-pair scope: 22, 16 and 5 per suite) plus, for `boundary-prefix`, its one baselined pair. The suite's other baselined pairs (held edges, other extensions) are reported as informational and are not required. The file is read from the archived PR4c receipts and passed as `--pairs`.
- 2.6 **Measurement 2, the replay.** `python3 -I scripts/ci-pr-affected-replay.py glob-rate --candidates receipts/candidates.tsv --list receipts/rows.txt --pairs receipts/pairs-scope.tsv --commits 200 --base $BASE --spot-check 3 --out receipts/glob-rate/`. The spot-check runs the real selector on three evenly spaced diffs (about a minute each warm) and a divergence stops the work; the model is fixed before anything else (CTO row 6). `receipts/glob-rate/glob-rate.tsv` is the stop-line table: Phase 3 touches only rows whose verdict is `glob` or `always_on`; every `baselined` row carries its reason code (`duration-over`, `duration-floor`, `duration-missing`, `rate-over-and-duration-over-30s`, `readings-disagree`, `no-complete-set`).
- 2.7 **Glob-half check against the real selector** (gate-passing suites that got a candidate set): create a detached scratch worktree at `$BASE`, append the candidate entries to the suite's array there, and run the real selector (`--print-selection --paths=<path>`) on one unit where the model says a glob-only hit and one where it says a miss, per suite (cold derive cache in a new tree: minutes for the first run, then tens of seconds). The real bit must equal the model's; a divergence stops the work. Remove the scratch worktree afterwards. This is the independent instrument for the half of the model the 2.6 spot-check cannot see.

### Phase 3 - apply the verdicts (skipped entirely when no row qualifies)

- 3.1 Claim (only now, because an index edit is going to happen): `gh pr edit 11226 --add-label s4-drain` and the mirror comment on #10448 (`gh pr list --label s4-drain --state open` was empty at 0.2). If nothing qualifies, no claim, no index edit and no #10865 comment: go to Phase 4.
- 3.2-3.4 land as ONE commit (the index edit, the accept-row deletions and the baseline prune): a commit between them has a baseline that differs from the live census and the lefthook ratchet blocks it.
- 3.2 `scripts/lib/test-affected-paths.sh`, only for qualifying suites: `glob` verdict, append the candidate entries to the suite's array (`AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS`, `AFFECTED_TESTS_SCRIPTS_ARGV_BEARER_SWEEP_PATHS`, `AFFECTED_PLUGINS_SOLEUR_TEST_BOUNDARY_PREFIX_TEST_SH_PATHS`, `AFFECTED_PLUGINS_SOLEUR_PATHS`); `always_on` verdict, add the registration label verbatim to `ALWAYS_ON_SUITES` (the `_MIN_ALWAYS_ON_DECLARED` floor only guards a gutted index and is not raised). Correct the grep-q-pipe-guard array comment that calls the whole-tree read an open selection-policy call. Whether the census accepts an always-on label that also has an edge array is checked by `bash scripts/lint-orphan-test-suites.sh`, not assumed.
- 3.3 `python3 -I scripts/ci-pr-affected-replay.py audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv`: delete the accept rows the audit reports `stale ... suite-always-on` for a suite that became ALWAYS_ON, by exact line; additions to the accept file stay out of this PR (PR4b row 6: never an accept row for a real whole-tree reader).
- 3.4 Prune the baseline: `python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline > ...baseline.tsv.new && mv`, then `ratchet --base origin/main` to exit 0. The diff is prune-only (at least one removed line, none added); state the four numbers (main's count, branch count, drained pairs of the verdict suites, extra drained).
- 3.5 Post-edit parity: run `glob-rate` on the edited tree with an empty candidate field for each edited suite. Its `existing_hits` must equal the Phase 2.6 `total_hits` for a `glob` suite and `units` for an `always_on` suite (existing edges now include the declared ones); then one real-selector run per edited glob suite on a glob-only unit asserts the bit is 1. No second spot-check.
- 3.7 Execute the rollback once before writing it down: in a scratch worktree run `git revert --no-commit` of the edit commit, then the ratchet and `bash scripts/lint-orphan-test-suites.sh`; the Rollback section below is written from that run.
- 3.6 Verification set (detached, results by rc file): replay suite, `bash scripts/test-all-affected.test.sh`, `bash scripts/test-affected-kb-consumers.test.sh`, `bash scripts/lib/inngest-probe-row.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `grep -oE '^AFFECTED_[A-Z0-9_]+_PATHS=\(' scripts/lib/test-affected-paths.sh | sort | uniq -d` prints nothing, shellcheck on touched shell, `bash scripts/markdown-lint.sh`. The index edit is a runner trigger, so the local `--affected` gate degrades to the full battery; CI's `test` context is the merge gate.

### Phase 4 - documentation and handoff

- 4.1 Runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`, section 7 ("The drain rubric"): correct the false "selection call" wording; add one exception clause, "except PR5's measured verdict, #10861", to the Breadth bullet ("no `ALWAYS_ON_SUITES` entry in a drain PR") and to the "Never in a drain PR" bullet (CTO round 2, T3: not widened to PR4b or PR4c); add a short procedure line naming the fresh duration plus 200-PR replay (`glob-rate`), the thresholds, and the rule that a `floor` or missing figure never qualifies; state that the hot-file budget does not apply to a glob. Do not edit the archived PR4c receipts.
- 4.2 Comment on #10861: the verdict table (suite, duration and source, both rates, verdict, reason code), what changed in the baseline, and what remains for the rest of #10861 by name (the `baselined` suites with their reason for an explicit call; `grep-q-pipe-guard` held edges unless it became ALWAYS_ON; `git-data-birth-readiness-gate`; the bulk readers and still-unproven recorder holds; the non-code pairs; the baseline deletion and the adoption-arm removal, the ADR-276 closing line, all of which wait on strict zero).

### Phase 5 - ship (no operator step)

- 5.1 Push, mark ready via `soleur:ship` (compound, review, QA are its phases). Before arming merge: `git fetch origin main`, merge it, re-run the ratchet on the merged tree and the overlap loop (Sibling PR Overlap), keep the worktree lease alive while waiting in the queue.
- 5.2 After merge, only if the index or baseline changed: comment the merge SHA on #10865 (the observation window restarts by hand; nothing in the probe enforces it).

## Files to Edit

- `scripts/ci-pr-affected-replay.py` (new read-only `glob-rate` subcommand, `durations_src`, docstring and argparse; the existing subcommands and `durations()` unchanged; it is the ratchet oracle, so the job prints the non-blocking `oracle-inputs-changed` notice).
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` (new section `== glob-rate (S4 PR5)`).
- `scripts/lib/test-affected-paths.sh` (only for qualifying suites; runner trigger).
- `scripts/ci-pr-affected-audit.baseline.tsv` (shrinks only, via `ratchet --print-baseline`).
- `scripts/ci-pr-affected-audit.accept.tsv` (deletions only, only the rows a newly ALWAYS_ON suite makes stale).
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (section 7).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-s4-pr5-glob-measurements/decision-challenges.md` (created by this planning run) and `tasks.md`.
- In `knowledge-base/project/specs/feat-one-shot-s4-pr5-glob-measurements/receipts/`: `measurement-stamp.txt`, `rows.txt`, `durations.tsv`, `pr-body-facts.md` (beside `receipts/`), `pairs-scope.tsv`, `candidates.tsv` (gate-passing suites only), `glob-rate/glob-rate.tsv` (the stop-line table; the tool emits verdict and reason) and its marker line, `retest/` (recorder output), the ratchet outputs; archived at ship.
- NOT edited: `scripts/test-all.sh`, `scripts/suite-durations*.tsv`, `scripts/suite-shard-legs*.tsv`, `scripts/audit-suite-reads.sh`, any workflow, ADR, `required-checks.txt`, ruleset or variable, the archived PR4c receipts.
- Files verified: every path under Files to Edit exists on `origin/main` (`git ls-files`); every glob named above is verified against `git ls-files` by the tool at Phase 2.4 (AGENTS `hr-when-a-plan-specifies-relative-paths-e-g`).

## Consumer of the declared lists

A declared entry is inert unless something reads it. The per-label array is resolved by name in `scripts/test-all.sh` (`_m="AFFECTED_$(_aff_label_map "$_l")_PATHS"`), each entry is minted into an anchored edge (`^glob:<pattern>` for a well-formed glob; a malformed one mints an always-match edge) and unioned with the derived edges; the selector's `AFFECTED_SELECTED` rows are what the audit, the ratchet and the new `glob-rate` read. An `ALWAYS_ON_SUITES` label is read by the same pre-pass (`if _affected_in_list "$_label" ${ALWAYS_ON_SUITES[@]+"${ALWAYS_ON_SUITES[@]}"}; then`) and makes the audit skip the suite. The accept file is read only by the audit's `load_accept` / `judge_rules`.

## Sibling PR Overlap

Open PRs whose files match the index, baseline, accept file, replay script or duration tables (`gh pr list --state open --json number,title,files`, 2026-10-26): #11154 (scheduled-orphan-sweeps Sentry monitor), #11147 (brand-hex commit gate), #10926 (npm-publish SIGPIPE), #7390 (WIP provenance build-arg). They move the live set and can conflict on the baseline, the accept file or the index tail. Mitigation: one drain PR at a time (the claim, Phase 3.1); take main's baseline and regenerate with the prune-only tool, never by hand; merge `origin/main` immediately before the push and re-run the ratchet on the merged tree; re-run the loop and `git merge-tree` right before arming merge.

## Open Code-Review Overlap

#8800 (test fixture: census sandbox shares inodes/symlinks with live repo) names `scripts/lib/test-affected-paths.sh`: Acknowledge, a different concern (a census-sandbox write-through hazard), the measurement never runs a census sandbox against the live tree. No open code-review issue names the baseline, the accept file, the runbook, the duration tables, the replay script or its test.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Work unit: S4 affected-index PR5 (#10861), measurement slice only." | Overview; Phases 0-5 | mapped |
| 2 | "Run PR5's two measurements FRESH on current origin/main, at this session's work time (store no numbers from earlier PRs)" | 0.1, 2.1-2.5 | mapped |
| 3 | "(1) per-suite duration from scripts/suite-durations.tsv for the 43 whole-tree/glob-read suites" | 2.2 (four suites; premise corrected) | mapped |
| 4 | "(2) the 200-merged-PR selection replay per glob (selection rate per candidate glob: edge)" | 1.1-1.3, 2.4, 2.5 | mapped |
| 5 | "If the replay tool cannot compute a per-glob selection rate over 200 merged PRs without extension, build that measurement first." | Phase 1 | mapped |
| 6 | "Then apply the row 6 policy as written ... including the boundary-prefix glob: decision from handoff-pr5-notes.md section 1." | 2.4, 2.6, 3.2 | mapped |
| 7 | "Stop line: no pair is globbed or added to ALWAYS_ON_SUITES unless both measurements were taken in this PR and meet the thresholds; otherwise it stays baselined and is listed for an explicit call." | 2.6 (verdict table), Guard Contract, 4.2 | mapped |
| 8 | "Holds stay in force: no CI_PR_AFFECTED, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run, no flip PR." | Non-Goals | mapped (held) |
| 9 | "Do not delete the baseline file in this unit unless the measurements and the remaining drain make strict zero reachable without violating a hold; report what remains for the rest of #10861 instead." | Overview 5, 4.2; CTO row 8 | mapped |
| 10 | "never ask the operator a technical question ... spawn soleur:engineering:cto ... Persist every decision as a row of the `\| Item \| Class \| Ruling \|` table in knowledge-base/project/specs/<branch>/decision-challenges.md" | Technical Rulings; decision-challenges.md rows 1-8 | mapped |
| 11 | "Plan only; the draft PR is #11226." | header; Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `glob-rate` subcommand in the replay tool | "If the replay tool cannot compute a per-glob selection rate over 200 merged PRs without extension, build that measurement first." | asked |
| encoded verdict function and boundary tests | "apply the row 6 policy as written" | asked (CTO row 7: the policy executable, not prose) |
| spot-check against the real selector | "Run PR5's two measurements FRESH" | inferred - justification: CTO row 6; the model decides 200 diffs without 200 selector runs, and an unchecked model could mislabel a suite |
| Phase 3 index edit, baseline prune, accept-row deletion | "ALWAYS_ON_SUITES entry when suite <=30 s and selected more often" and "glob: edge when suite <=60 s" | asked (conditional on a qualifying verdict) |
| scratch-worktree glob-half check (2.7) | "Run PR5's two measurements FRESH" | inferred - justification: the real selector does not have the candidate globs, so the spot-check cannot validate the glob half of the model; this check is the independent instrument (plan-review, Kieran P1) |
| runbook section 7 edit | "report what remains for the rest of #10861" | inferred - justification: the executed procedure and the amended hot-file statement must have one home so a later author applies the same bar |
| `s4-drain` claim and #10865 comment | "Holds stay in force" (the series' standing claim rule) | inferred - justification: runbook "The drain claim" requires one drain PR at a time and a recorded merge SHA when the baseline moves |

### Split Assessment

- Subsystems touched: 2 (CI machinery under `scripts/`, knowledge-base docs).
- Planned files: 6 edited + 1 to 12 created; estimated changed lines: about 250 for the subcommand and its tests, a handful of index lines, baseline lines removed only for qualifying suites.
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines. None met.
- Recommendation: single PR. The tool and the verdicts ship together because the stop line requires the measurements to be taken in the same PR.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing today, because the lever (`CI_PR_AFFECTED`) is unset and locked and the ratchet job is advisory. After a later, separately authorized flip, a pull request that changes a file a whole-tree reader scans could merge without that suite having run if a glob were narrower than the suite's real scan (a false negative), or every PR would pay for a suite it does not need if a glob were wider than necessary.
**If this leaks, the user's [data / workflow / money] is exposed via:** no data path (the work reads tracked repository text and CI metadata and runs local suites for timing); the exposure is CI minutes (money) if an edge or an always-on entry is over-broad once the lever flips.
**Brand-survival threshold:** aggregate pattern

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** eight technical forks ruled on 2026-10-26 (rate definition, denominator and non-attributable units, duration gaps, candidate-set rule, hot-file budget scope, tool placement, encoded verdict, baseline and slice scope); see Technical Rulings. No product, marketing, legal, finance, operations, sales or support implication: internal CI index maintenance, no user-facing surface, no data processing change, no new vendor or spend. Product/UX gate: none (no `components/`, `app/**/page.tsx` or layout file in Files to Edit/Create).

## Architecture Decision (ADR/C4)

No new architectural decision: this executes the standing PR4b row 6 and PR4c row 7 rulings inside ADR-242 decision 22 (the `glob:` kind) and ADR-276 item 3 (PR5 takes the rest). ADR-276 is not edited and its closing Stage-status line is not appended in this slice (CTO row 8); the procedure goes to the runbook.
C4: no impact. Checked against `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`: no external human actor, external system, data store or actor-to-surface access relationship changes (the index, the baseline, the replay script and the receipts are repository-internal CI machinery); a grep of the three files finds no element for the affected index or its always-on set, and no workflow, job, monitor or heartbeat is added or removed, so the derived cardinalities in edge prose do not move (`plugins/soleur/test/c4-count-parity.test.sh` stays green in the full battery).

## Guard Contract

The stop line is a gate: a verdict function that decides whether the index may be edited. It is written here as a contract before the code.

### Guard 1 — the PR5 stop-line verdict

**Property.** No suite receives a `glob:` entry or an `ALWAYS_ON_SUITES` label unless a measurement taken in this PR, at the recorded `origin/main` SHA, shows a `measured` duration within the threshold and a total selection rate on which the conservative and the excluded reading agree; every other suite is `baselined`.
**Assembly.** The property quantifies over every path from a measurement to an index edit: (1) the verdict function inside `cmd_glob_rate` (the one chokepoint, called for every candidate suite, not only the first), (2) the per-suite rows of `receipts/glob-rate/glob-rate.tsv` (the tool emits verdict and reason; there is no hand-assembled verdicts file), (3) the Phase 3.2 edit of `scripts/lib/test-affected-paths.sh`, which could be made by hand without a verdict row. Path (3) is closed by the pre-merge check in Acceptance Criteria: every `glob:` entry and every `ALWAYS_ON_SUITES` label added by the diff maps to a `glob` or `always_on` row of `glob-rate.tsv` (array name to suite label, then verdict) whose recorded base SHA is an ancestor of HEAD.

**Mutation matrix.**

| # | Mutation (must turn the suite RED) | Targets |
|---|---|---|
| 1 | table-driven boundary: duration 60001 with a low rate returns `glob`; duration 30001 with a high rate returns `always_on`; rate 51 of 200 returns `glob`; rate 50 of 200 returns `baselined`; `src=floor` or a missing row returns anything but `baselined` | verdict function: thresholds, inclusive sides, duration provenance |
| 2 | the two readings disagree and the verdict is not `baselined` | R2 agreement |
| 3 | the selector rows file is empty, the commit list is empty or the spot-check sample is empty and the run exits 0 (a vacuous "0%" that reads as `glob`) (a vacuous "0%" that reads as `glob`) | the guard's own dispatch |
| 4 | a second candidate suite is added after a compliant first and is judged by the first suite's duration or rate (first-member-only check) | second member |
| 5 | a candidate set that leaves a baselined pair of its suite unhit still returns `glob` | coverage of the pairs |
| 6 | the union is replaced by glob-only (or by existing-only) in the total rate | rate definition (CTO row 1) |
| 7 | a runner-changed or not-evaluable unit is dropped from the conservative reading | denominator (CTO row 2) |

No reorder row: the verdict has no order or lifetime property (it is a pure function of its row), so a reorder mutation would measure nothing.
**Harness rows.** (a) Edit the suite, not the guard: make the stub selector print no `AFFECTED_SELECTED` rows; the section must go RED (a harness whose success is "no failure" passes on zero rows). (b) Must-PASS non-canonical input: a candidates file with comment and blank lines, CRLF line ends, shuffled suite order and one extra suite not in the canonical fixture yields the same verdicts as the canonical file; a guard that rejects everything is invisible to RED rows and is caught only here.
**Anchor.** The receipts and the index edit land in the same commit set, so a PR can edit both: the control proves consistency of this PR, not integrity. What must also move for a weakening to pass: the base SHA in the receipts must be an ancestor of HEAD and recent enough that `git rev-list --count <sha>..origin/main` is small (stated in the PR body), the real-selector spot-check is an instrument independent of the model, and a reviewer re-runs the one `glob-rate` command (read-only, deterministic on the same SHA) and diffs `glob-rate.tsv`. No required review exists in this repository's ruleset (ADR-276 PR3a residual (a)), so review is a routing control only.

## Observability

The change is CI index data and a read-only replay subcommand under `scripts/`; it adds no emitter and no scheduled task. The standing signal is the advisory ratchet job's marker line; the new subcommand prints its own marker.

```yaml
liveness_signal:
  what: the marker line SOLEUR_PR_AFFECTED_RATCHET exit/reason/live/baseline printed last by the affected-index-ratchet job (exit 0 reason pass means live equals the pruned baseline), and SOLEUR_PR_AFFECTED_GLOB_RATE printed by the new subcommand when it is run
  cadence: every pull_request and merge_group run for the ratchet job (drafts and bots included); on demand for glob-rate
  alert_target: the job's own ::error annotation and a red check on the PR check list (advisory until PR3b; no pager)
  configured_in: .github/workflows/ci.yml job affected-index-ratchet (unchanged by this PR); scripts/ci-pr-affected-replay.py glob-rate

error_reporting:
  destination: GitHub Actions job log, step summary and the ::error title=affected-index-ratchet annotation; glob-rate writes exit code 2/3/4 and one stderr reason line
  fail_loud: ratchet exit 1 (a verdict about the tree) or exit 2 (infrastructure) renders the job red with the reason token; glob-rate never exits 0 with a refused input, a failed read or a spot-check divergence

failure_modes:
  - mode: a glob is narrower than the suite's real scan, so a PR that changes a scanned file skips the suite after the lever flips (false negative)
    detection: not visible to the ratchet (declared limit); bounded before merge by the scan-scope derivation, the directory-completeness check against git ls-files, the coverage-of-baselined-pairs check and the real-selector spot-check
    alert_route: PR review of receipts/candidates.tsv and glob-rate.tsv; demotion of the glob in a follow-up with evidence
  - mode: the model and the real selector disagree on a diff (an edge the model does not see, a fallback other than runner-changed)
    detection: glob-rate --spot-check exits 4 naming the suite and the diff before any verdict is accepted
    alert_route: the work stops; the model is fixed first (CTO row 6)
  - mode: a sibling merge moves main so the measured SHA is stale or the baseline no longer equals the live set
    detection: ratchet exit 1 new-pair or stale-line on the merged tree; the receipts name a SHA that is no longer the PR base
    alert_route: red check on the PR and the queue entry; re-run Phases 2 and 3 on the new SHA

logs:
  where: GitHub Actions run logs of the affected-index-ratchet job plus the --report file; local receipts under knowledge-base/project/specs/feat-one-shot-s4-pr5-glob-measurements/receipts/
  retention: the repository's Actions log retention (default 90 days); the receipts persist in the spec directory and its archive

discoverability_test:
  command: grep -o -e 'SOLEUR_PR_AFFECTED_GLOB_RATE' scripts/ci-pr-affected-replay.py
  expected_output: SOLEUR_PR_AFFECTED_GLOB_RATE
```

## Test Scenarios

The Acceptance Criteria are the single list of checks; the scenarios name only controls not restated there.

1. The "existing edges" input is the pre-edit `rows.txt`; after Phase 3 an empty-candidate run on the edited tree reproduces `total_hits` (glob) or `units` (always_on) as `existing_hits` (3.5). Taking `rows.txt` after the edit would double count the glob and hide a mistake.

## Acceptance Criteria

### Pre-merge

- [ ] `git diff --name-only origin/main...HEAD` (three dots) lists only: `scripts/ci-pr-affected-replay.py`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`, the runbook, this plan, and files under `knowledge-base/project/specs/feat-one-shot-s4-pr5-glob-measurements/` (or, after the ship-time archive, `knowledge-base/project/specs/archive/*pr5-glob-measurements*`), plus - only when a suite qualified - `scripts/lib/test-affected-paths.sh`, the baseline and the accept file; no workflow, ADR, `required-checks.txt`, ruleset, duration or shard table, `scripts/test-all.sh`. Files that `soleur:compound` and `soleur:ship` write on this branch are allowed and nothing else: `knowledge-base/INDEX.md`, `knowledge-base/project/learnings/**`, and `knowledge-base/project/specs/feat-one-shot-s4-pr5-glob-measurements/session-state.md` (or their archive paths).
- [ ] Both measurements were taken in this PR: `receipts/measurement-stamp.txt` names the `origin/main` SHA and UTC date, `git merge-base --is-ancestor <sha> HEAD` is true, `git rev-list --count <sha>..origin/main` is stated in the PR body, and `receipts/glob-rate/glob-rate.tsv` was produced by the committed tool (re-running the Phase 2.6 command with `--base <sha>` reproduces the table byte for byte; the date is only in the marker line). If, after the final merge of `origin/main`, the changes since `<sha>` touch `scripts/lib/test-affected-paths.sh`, the baseline, the accept file, the duration tables or the replay script, Phases 2 and 3 are re-run on the new SHA; otherwise only the ratchet is re-run. No number in any file comes from an earlier PR or from the planning session.
- [ ] `receipts/glob-rate/glob-rate.tsv` has one row per measured suite (four rows) with duration, `src`, both readings of the rate, `ci_seconds_added`, the tool's verdict and, for each `baselined` suite, a reason code from the closed list in 2.6; the PR body carries the table and the list of suites left for an explicit call, says the `floor`/missing verdicts follow CTO row 3 rather than a literal reading of the quoted policy, and, if a local timing was taken, labels it "local, not CI class, informational".
- [ ] The stop line holds mechanically: take the added non-comment lines (`git diff -U0 origin/main...HEAD -- scripts/lib/test-affected-paths.sh | grep -E '^\+[^+]' | grep -vE '^\+[[:space:]]*#'`); every added `"glob:..."` entry sits in the array of a suite whose `glob-rate.tsv` verdict is `glob`, and every added `ALWAYS_ON_SUITES` label is a suite whose verdict is `always_on` (array name to label mapping is the index's own `AFFECTED_<LABEL>_PATHS` rule); with zero qualifying rows the index, baseline and accept file are byte-identical to `origin/main` (`git diff --stat origin/main...HEAD -- <the three>` is empty), and no `s4-drain` label, mirror comment or #10865 comment exists.
- [ ] The `boundary-prefix` decision is in `glob-rate.tsv` with its reason; the PR body states that the hot-file budget did not decide it (ruling 5).
- [ ] When a suite qualified: `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` exits 0 with `live == baseline`; the baseline diff is prune-only (at least one removed line, no added line), C-locale sorted with a final newline, and the four numbers are in the PR body (main's line count, the branch's, the drained pairs of the verdict suites, the extra drained); every accept-file change is a deletion of a row the audit reported `suite-always-on`; the final audit shows zero stale rows and zero new pairs.
- [ ] Every fact that these criteria say belongs "in the PR body" is first written to `knowledge-base/project/specs/feat-one-shot-s4-pr5-glob-measurements/pr-body-facts.md` (the ship skill replaces the PR body from the diff and folds this file in); the criterion is checked against that file.
- [ ] No variable, lock, ruleset or `CI_PR_AFFECTED` change; the baseline file still exists; `grep -n 'Stage status' knowledge-base/engineering/architecture/decisions/ADR-276*.md` shows no new dated line from this PR; none of `collect`, `ejections`, `aggregate`, `verdict` was run (the receipts contain only `glob-rate`, `audit`, `ratchet` and the recorder output).
- [ ] The new test section is green and its mutation rows 1-7 and harness rows (a)-(b) of the Guard Contract exist and fail on their mutants; `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-26-ci-s4-affected-index-pr5-glob-measurements-plan.md` exits 0.
- [ ] CI's `test` context is green; the replay suite rc 0 (local, detached); the local full affected gate state is stated (rc from its rc file, or `not finished at <time>, CI test context is the gate`); orphan census, `scripts/test-all-affected.test.sh`, `scripts/test-affected-kb-consumers.test.sh`, `scripts/lib/inngest-probe-row.test.sh`, shellcheck and `scripts/markdown-lint.sh` rc 0; the `uniq -d` check on `AFFECTED_*_PATHS` prints nothing.
- [ ] #10861 carries the Phase 4.2 comment (verdict table, baseline movement, what remains by name); the PR body uses `Ref #10861`, `Ref #10448`, `Ref #9729` only, restates the holds and the local-gate degradation, and says the baseline file and the ADR-276 closing line wait for strict zero.
- [ ] `origin/main` was merged into the branch immediately before arming merge, the lease file existed, and no push followed the arming (one PR comment with the ancestor-check result and the head SHA).

### Post-merge

- [ ] If the index or baseline changed: the merge SHA is commented on #10865 (window restart) and `gh pr list --label s4-drain --state open` is empty again.

## Rollback

Revert the merge commit: the index entries, the baseline lines and the deleted accept rows return together (the baseline stays equal to the live set because the ratchet compares them as a set). The `glob-rate` subcommand is read-only and unused by any workflow, so reverting it has no runtime effect. Nothing here flips a lever.

## Non-Goals

- No `CI_PR_AFFECTED`, activation-lock removal, PR D (#10414), PR3b (#10859), evidence re-run or flip PR.
- No baseline deletion, no adoption-arm removal, no ADR-276 closing line, no accept rows for a real whole-tree reader.
- The 31 `grep-q-pipe-guard` exact-file edges (unless that suite becomes ALWAYS_ON, which drains them as a side effect), `git-data-birth-readiness-gate`, the bulk readers, the still-unproven recorder holds and the non-code pairs stay for the rest of #10861 by name; they are listed in the #10861 comment, not drained here.
- No regeneration of `suite-durations*.tsv` or the shard tables.
- No deferral issue is filed: each deferred item is already tracked on #10861 (the handoff names them), and the explicit-call list goes into its comment.

## Risks and Sharp Edges

- The selector is slow (cold run in minutes, warm in tens of seconds at plan time) and reads `scripts/lib/test-affected-paths.sh` while it runs: take `rows.txt` before any edit and never edit the index during a run; the spot-check budget is three sampled diffs.
- `rows.txt` is the PRE-edit edge set. Re-running the model on a post-edit `rows.txt` counts a declared glob as an existing edge; 3.5 uses an empty candidate set for exactly that reason.
- A root-anchored `glob:` entry (`/`-free head) matches only dir-less paths, so a tree-wide extension read is many entries; a wider-than-scan entry inflates the rate without protection (the tool prints the excess), and an entry that is malformed always matches (the tool refuses it).
- `src=floor` and missing rows make two of the four suites unmeasurable by the named source; the expected outcome for them is `baselined` with the reason code, and that is a finding for the explicit call, not a defect to be hidden by a local timing.
- A runner-changed unit is a diff that touches `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh` (the model uses `--paths`, which skips the registration-only classifier, so it counts a diff the real gate would bound as runner-changed); under the conservative reading these count as selected for every suite and can be a large share of the 200 on their own, so the tool prints that share per run and the two readings are expected to decide the verdicts. The two readings are printed side by side and disagreement is `baselined`.
- Accept rows are keyed to mention lines; deleting the rows of an ALWAYS_ON suite is the only accept-file edit allowed here, and a sibling merge that changes a mention line turns a surviving row stale (rebuild from main's file, deletions only).
- Do not store a duration, rate or count in any file before it is produced by the Phase 2 command on the recorded SHA.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it.
