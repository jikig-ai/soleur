---
title: "chore(ci): affected-gate follow-ups — committed read recorder and re-priced demotions (PR-B), runner as closure leaf and heavy-battery audit (PR-C), shard-leg regeneration (D5)"
type: chore
date: 2026-10-02
slug: affected-gate-reprice-recorder-runner-leaf
branch: feat-one-shot-shard-legs-reprice-recorder-runner-leaf
issue: 9307
closes: []
priority: medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# chore(ci): affected-gate follow-ups — recorder + re-priced demotions (PR-B), runner leaf + heavy batteries (PR-C), shard-leg regeneration (D5)

## Enhancement Summary

**Deepened on:** 2026-10-02
**Passes:** mechanical halts (4.6 user-brand, 4.7 observability, 4.8 PAT grep, 4.10 encryption: not triggered, 4.11 guard contract lint: green); architecture-strategist, test-design-reviewer, security-sentinel, git-history-analyzer (attribution and run verification); local measurements of the inotify mechanics and the enumerate stream; earlier plan-review panel (DHH, Kieran, code-simplicity, CTO) and SpecFlow.

### Key improvements

1. **The recorder's overflow detection was impossible as designed.** `inotifywait` delivered 16,384 events for 17,500 distinct opens and printed no `Q_OVERFLOW`; a python3 raw-inotify reader saw `IN_Q_OVERFLOW`. The event source is now a committed python3 reader, which also removes the `inotify-tools` dependency and lets CI drive the real reader.
2. **Isolation corrected.** A `git worktree` shares `.git` with the live repo and ~70 suites run mutating git commands; the recorder now audits a private `git archive` checkout under `env -i`, a scratch PATH, a network-less namespace and per-suite process groups, with nonce sentinels and contamination checks.
3. **A5's "explained removal" rule corrected** from a literal-text test (unsound for the ~475 second-hop edges) to an independent closure walk; the leaf array renamed `CLOSURE_LEAF_FILES` to stay outside the census linter's `AFFECTED_` scan; `./` paths normalised; staged-scope row pinned; every runtime-read data file the recorder finds gets a CI-resident declared edge.
4. **`scripts/domain-model-drift` (B2) moved to Phase 2.6**, after A5 removes the very cost that kept it always-on.
5. **D5 made reproducible** (explicit `--timings-dir` per downloaded run, `push` events on `origin/main` only, per-label delta sanity) instead of `--runs 5`; its placement stays last and peelable.
6. **Guard matrices tightened** (rc plus message on every RED row, population floors, conditional D2 matrix with machine-checked baseline classification, D4 m9 twin and dispatch row) and the cited-fact table corrected (#9402 is the issue, #9407 the PR).

### New considerations discovered

- ADR-242 decision 17 supersedes decision 15's "one audited run" caveat; decision 18 amends decision 16's identity-contract wording; the amendment goes before `## References`.
- The kernel coalesces identical consecutive inotify events, so repeat opens are invisible by design (irrelevant to which-files evidence, recorded as a blind spot).
- Four of five reviewers independently recommended cutting D4 and splitting D5; both stay conditional or peelable per the brief (see `decision-challenges.md`).

## Overview

Umbrella issue 9307 ("affected-only, parallel test gate") shipped PR 1 (`9c5252e644`, anchored edges, always-on audit, dropped-consumer
ratchet) and PR-A (`fdd690ea49`, the identity-preserving 2.5x to 4.6x cheaper pre-pass). Its last two comments re-filed the rest of the
PR 1 residuals with measured reasons and **nothing there was started**. This plan implements them:

| Piece | Definition (source) | Selection effect |
|---|---|---|
| **PR-B** | B1 committed recorder `scripts/audit-suite-reads.sh`; B2 re-demote `scripts/domain-model-drift` and re-price the 23 existing demotions with the recorder; B3 "Round 2" in the always-on audit; D2 ratchet breadth; D3 subcommand-form minting; D4 deleted declared subject still selects | changes by design, each re-baselined |
| **PR-C** | A5 runner and its index as closure leaves (the measured route to a further order of magnitude on the pre-pass); D1 `REPO_ROOT` idiom fix, decided together with A5; Phase C narrowing of the heavy always-on batteries, only with evidence | A5 narrows, D1 widens, Phase C narrows only per suite with evidence |
| **D5** | `python3 scripts/regenerate-shard-manifest.py ... --write` from at least five green CI runs of main (five explicit `--timings-dir`s; Phase 3) | none (data refresh) |

PR 2 (plugin-shipped stack-detecting gate) and PR 3 (opt-in shard launcher) of the umbrella are **out of scope and untouched**.

**Where PR-B and PR-C are defined.** The four plans named in the brief (`2026-09-23-feat-ci-test-shard-speedup-phase-2`,
`2026-09-25-feat-ci-test-scripts-sharding`, `2026-09-26-feat-ci-orphan-suite-rows-split`, `2026-09-24-chore-retire-ci-leg-durations-8006`) contain
none of the strings "PR-B", "PR-C", "recorder", "runner leaf" or "demotion" (grep-verified). The definitions live in (1) the last two comments of
issue 9307 and (2) the archived PR-A plan `knowledge-base/project/plans/archive/20261002-033030-2026-10-01-feat-cheap-affected-prepass-and-pr1-residuals-plan.md`
sections "PR-B (follow-on; design level)" and "PR-C (follow-on; design level)". This plan takes those as authoritative and re-measures every figure
they quote (several are stale; see Research Reconciliation).

### Delivery shape

One branch, one PR, **three ordered phases, each ending in its own revertable commit set** with its own acceptance and its own re-baselined
streams. The brief asks for all three pieces; the seam between PR-B and PR-C is nevertheless the one the PR-A review split on (selection-changing
work in a diff that touches `scripts/test-all.sh` degrades the local gate to a full run and leaves CI as the only gate). The Split Assessment below
therefore recommends a split, the plan proceeds as a single PR per the brief, and the choice is recorded as a challengeable decision in
`knowledge-base/project/specs/feat-one-shot-shard-legs-reprice-recorder-runner-leaf/decision-challenges.md`. Cut order if scope pressure appears:
D4 first, then D1 (already evidence-gated), then Phase C narrowing (the audit itself stays), then A5. Phase 2 starts only after Phase 1 is green on CI with its parity fingerprint recorded; Phase 3 is the first piece to peel into its own data-refresh PR if the merge order with PR 9409 makes it awkward. PR-B's recorder is the dependency of A5 and Phase C evidence.

## Research Reconciliation — Spec vs. Codebase

| Claim (source) | Reality (verified on `origin/main` 493c859960, this worktree) | Plan response |
|---|---|---|
| The four named plans define PR-B / PR-C (brief) | They do not; definitions are in issue 9307 comments + archived PR-A plan | Interpretation recorded in Overview and Decisions |
| Phase C candidates are `scripts/test-all-affected` (442 s), `lint-orphan-test-suites-mutations-a/-b` (422/424 s), `test-all-infra-coverage-notice` (83 s), "together 1,371 s of 39.3 min" (PR-A plan) | The first three were **already withdrawn from `ALWAYS_ON_SUITES` by ADR-262** (`AFFECTED_CONSUMED_EDGES` rows "ADR-262" in `scripts/lib/test-affected-paths.sh`); `ALWAYS_ON_SUITES` is 119 entries and sums to ~1,147 s (19.1 min) of `scripts/suite-durations.tsv`, not 39.3 min | Phase C scope shrinks to the **six** heavy always-on batteries still in the array (561 s); the three withdrawn ones get one status line in the audit, no work |
| "18 non-always-on registrations whose closure reaches the runner, about 450 edges" | `--print-selection --paths=README.md` today: **16** `edge:derived` rows carry `^scripts/test-all.sh`, each with 472-476 edges (32 rows counting declared edge sets that name the runner explicitly) | A5 re-measures its delta at work time; the figure 18 is not quoted in any AC |
| "23 `^README.md` edges arrive through the runner closure" (D1) | The current README-probe stream has **no row carrying `^README.md`** (2 lines mention the string inside other paths) | D1 is decided on a fresh census of suites whose text uses the `REPO_ROOT=$(cd ... /..)` idiom, not on the 23 figure |
| "`scripts/domain-model-drift` derive cost is 0.3 s after PR-A" (PR-A plan) | Unmeasured on this tree | Phase 1 measures it with `--print-selection` before and after the demotion; demotion lands only if the measured derive cost stays small |
| D3 "a two-line change" | The skip is a `case "$_prev $_tok"` list in `_affected_derive` (`bun test`, `npm test`, ...) and the `-c` payload loop (`for _w in $_tok`) has **no** skip at all | D3 touches both sites; rows first |
| D4 "about 22 slash-less declared directory entries" | Confirmed: 22 declared array entries are existing directories without a trailing slash (listed by the census one-liner in Phase 1.3) | Migration is a prerequisite commit inside D4 |
| D5 "after merge, from the post-change code" | Five green main `ci.yml` runs that already contain PR-A exist now (36949041665, 36951949236, 36953170228, 36961928071, 36969101769); the committed light manifest header still says `generated-from-runs=incremental` | D5 runs in this PR as its last commit; PR 9409 (open, no longer a draft) independently regenerated the same files from older runs (see merge-risk table) |
| ADR-242 forward reference: runner leaf is "decision 18" | The PR-A plan assigned 17 to the leaf and 18 to D4 (swapped) | Numbers follow landing order: **17 = PR-B** (D4 mint + recorder evidence contract), **18 = PR-C** (runner leaf + D1 + Phase C), matching the ADR text |
| `strace` unavailable, recorder is inotify (via `inotifywait`) | `inotifywait` is installed but was measured to drop `IN_Q_OVERFLOW` silently; `strace`, `perf`, `bpftrace`, `fatrace` are not installed; `python3` raw inotify via `ctypes` works and sees the overflow | Recorder reads inotify through a committed python3 reader (`scripts/lib/inotify-open-recorder.py`); `inotifywait` is not used |

## Research Insights

### Premise Validation (Phase 0.6)

Checked: issue 9307 (open, umbrella; the last two comments carry the scope); PR 9409 (open draft, branch `feat-one-shot-9400-prepush-ratchet-lane`, 20 files
including the three scripts and both TSVs); PR 9220 (merged 2026-09-29, the fix-forward) and commits `abd29f4bcf` / `ed804aecff` (exist; revert of
`tests/hooks/incidents` from the sandbox keep-list in `scripts/test-all-affected.test.sh`); `scripts/audit-suite-reads.sh` does **not** exist on
`origin/main` (nothing started, as the brief says); ADR-242 and ADR-240 exist; ADR-262 already moved three of the four Phase C candidates (stale premise,
reconciled above); ADR corpus grep for "recorder", "inotify", "closure leaf": only ADR-242 (decisions 15-16 and their forward references) — no rejected-alternative
conflicts: ADR-242's alternatives table rejects "observe reads with strace" (unavailable) and "run the ratchet over declared arrays only", neither of which this plan proposes.

### Property List and Cut List (Phase 0.6b)

Properties the ask buys:

1. A maintainer can reproduce, from a committed tool, the evidence that decides whether a suite may leave the always-on set (today it is session scratch).
2. A recording that is incomplete (queue overflow, failed watches, rc non-zero) or whose suite probes a path outside its cover can never yield "demotable".
3. The 23 existing demotions plus `scripts/domain-model-drift` are priced on evidence that includes those disqualifiers (one of four ratchet hits in PR 1 was a real uncovered read).
4. The ratchet and the minting rules see the read/subcommand forms that surface real uncovered suites or false edges today, and each added form is pinned by a fixture row.
5. The local pre-pass stops paying for what the runner's text merely names, without dropping any edge the runner really sources.
6. `REPO_ROOT` idiom suites carry the edges their text actually names (a soundness widening). **Evidence-gated:** the issue's "23 `^README.md` edges" premise did not reproduce, so D1 is implemented only if the Phase 0.4 census finds at least one suite whose text names an existing repo file the derive misses.
7. A heavy always-on battery leaves the set only when three pieces of evidence agree; the default is keep.
8. The shard manifest reflects measured durations of the code that is on main now (the ratchet and the pre-pass-heavy suites are currently floor-weighted or stale).
9. Phases 1 and 2 move no existing suite's shard leg in the sandbox positional mode or in manifest mode (the s1/s2 parity class); Phase 3 moves legs by design, through the generator only.

Cut List (mechanism -> property -> what already covers it):

- Committed `--perturb` and `--corpus 60` flags for Phase C -> property 7 -> two or three suites at most are candidates (see value measurement); the perturbation and 60-commit corpus checks are run as documented one-off command lines recorded in the audit, not as committed tooling.
- `--json` output and parallel suite execution for the recorder -> property 1 -> serial TSV is the contract the audit already used.
- A committed ordinal-fingerprint guard for the sandbox keep-list -> property 9 -> `scripts/test-all-affected.test.sh` rows s1/s2 are already the oracle and this PR's diff touches the runner so the battery runs; the fingerprint is a work-phase verification command, not a guard.
- Forms for D2 that surface no real uncovered suite today -> property 4 -> measured first against the 541 registrations; unmeasured forms are listed as "still unseen" in the oracle header, not implemented.
- Re-auditing the three ADR-262-withdrawn batteries -> property 7 -> already narrowed by ADR-262; one status line only.
- Recorder surface (review panel, mechanical): `--propose-cover` (the only new-demotion use is hand-declared today), `--markdown` (24 rows paste from the TSV), the newline-in-path and symlinked-cover checks (not a threat model for an operator-run audit), and the static scan over every script the recording observed opened (replaced by a grep over the suite file itself plus named blind spots) -> properties 1-2 -> the core (overflow, failed watches, rc, probe outside cover, cover comparison, zero-suite floor) covers them.
- Guard entries 5 (generator output) and 6 (parity) as Guard Contracts -> properties 8-9 -> they reuse existing tests (`scripts-shard-manifest`, `test-all-affected` rows s1/s2); they become verification gates under Technical Considerations.
- D1's independent added-edge resolver -> property 6 -> built only if the Phase 0.4 census says D1 lands.
- D4 is **kept but cut-first**: its property (a deleted declared subject still selects its suite) is partly covered today because the census linter reports the dangling declaration in the same run; the residual gap is that the guarded suite itself does not run on the deleting diff.

### Value-proposition measurement (Phase 0.6c)

Baseline measured at plan time on a loaded host (load average 12.6, 16 cores): `time bash scripts/test-all.sh --print-selection --paths=README.md`
= real 119.8 s, user 102.5 s, sys 20.5 s (rc 0; 541 rows; 119 always-on, 297 edge:derived, 125 edge:declared). The 16 derived rows that reach the runner each
carry 472-476 edges. The PR-A comment attributes 61.9 s CPU to following what the runner text names; A5's claim is therefore "most of ~123 s CPU", to be
**re-measured by the bench after the change**, not assumed. Command that produced the numbers: the `time` line above; the row census is
`awk -F'\t' '$1=="AFFECTED_SELECTED"&&$4=="edge:derived"' <stream>` joined on `^scripts/test-all.sh`.

Phase C value: always-on suite time is `awk` over `scripts/suite-durations.tsv` for the labels in `ALWAYS_ON_SUITES` = 1,146.6 s (119 labels, 2 without a row). The six
remaining heavy members: `scripts/test-contention` 134 s, `plugins/soleur/test/operator-ack-guard.test.sh` 108 s, `tests/scripts/sentry-alert-live-fidelity` 102 s,
`scripts/test-all-infra-coverage-notice` 83 s, `scripts/lint-orphan-test-suites` 68 s, `plugins/soleur/test/hook-input-classification-mutation.test.sh` 66 s = 561 s
(49% of always-on time at the extreme; realistic outcome one or two suites, 83-191 s). B2's saving is ~0.9 s of suite time (suite count, not time); its
value is that it is the recorder's first customer and corrects a decision made on a first-touch attribution that PR-A withdrew.

D5 value: the light manifest is not measured today for the ratchet (`scripts/test-affected-kb-consumers` is `src=floor`, 871 ms, on leg 2) although PR 9409's
own regeneration measured it at 262 s; a floor-weighted 4-minute suite on a leg that already sits near the ~10-minute ceiling is the leg-balance defect D5 exists to fix.

### Repo research (key anchors, all in this worktree)

- Derive and classifier: `scripts/test-all.sh` — `_affected_file_edges_uncached` (three passes: source/import edges, invocation tokens, `$VAR/path` tokens), `_affected_edge_token` (the `$(cd ... && pwd)` replacement that loses `/..` is the D1 defect), `_affected_derive` (argv skip list `bun test|npm test|...`, `-c` payload loop, name-stem fan-out, closure to depth 8), `_affected_add_edge` (existence filter + `^` anchoring), `_MIN_ALWAYS_ON_DECLARED=116` (pinned by `scripts/test-all-affected.test.sh` row f1).
- Declarations: `scripts/lib/test-affected-paths.sh` — `ALWAYS_ON_SUITES` (119), `AFFECTED_CONSUMED_EDGES` (ADR-262 rows), "ALWAYS-ON AUDIT DEMOTIONS (#9307)" block, the `scripts/domain-model-drift` always-on entry (line ~214).
- Ratchet: `scripts/test-affected-kb-consumers.test.sh` (python oracle: `KB` regex literal `knowledge-base/` only, one hop, fixture-context skip) and `scripts/test-affected-kb-consumers.baseline.txt`; regenerated with `--write-baseline`.
- Bench: `scripts/affected-prepass-bench.sh` (identity contract with `--added` / `--added-edges` declared deltas; no removed-edge mode).
- Recorder method: `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md` (Method, Disqualifiers, Reproducing the recorder, 24-row table). Original queue-overflow note: "inotify queue overflow was not checked for"; host `max_queued_events` 16384 vs one suite opening 16,636 files.
- Shards: `scripts/regenerate-shard-manifest.py` (sticky-LPT, `--runs N` = last N green main `ci.yml` runs, `--incremental` for add/remove, paired `suite-durations*.tsv`), `scripts/suite-shard-legs.tsv` (n=7), `scripts/suite-shard-legs-heavy.tsv`, `_shard_selects` (manifest-mode label lookup, untabled labels hash by `cksum`; **positional fallback** `(ordinal-1) % N` when no manifest is active).
- The parity class (`abd29f4bcf`, `ed804aecff`): `scripts/test-all-affected.test.sh` builds a sandbox copy of the live runner trimmed to a keep-list of 8 labels (`run_suite` case filter, ~line 200); the sandbox has no manifest so shard legs are **positional over the trimmed stream**. Adding `tests/hooks/incidents` early in that stream moved the single selected suite (`scripts/lint-dual-lockfile`, always-on) onto the dark leg under `SCRIPTS_SHARD=1/2` (ran=0). Any edit that adds, removes or reorders a kept label, or removes `scripts/lint-dual-lockfile` from `ALWAYS_ON_SUITES`, is in the class. Registrations of non-kept labels are invisible to the sandbox; the repo convention (comment blocks in `test-all.sh`) is to register new suites **last in their block**.
- Learnings applied: `2026-09-29-my-elif-arm-ate-the-selection-walk-...` (never put telemetry in a dedicated `elif` arm of the pre-pass ladder; A5 must not touch the ladder), `2026-09-25-matrix-k-cannot-split-an-atomic-suite` (read the predicted leg table before judging a regen; an atomic suite longer than the ceiling is not fixable by K), `2026-09-22-one-shared-json-leaf-made-every-pair-of-prs-conflict` and ADR-235 (generated artifacts: re-run the generator, never hand-merge), `2026-09-22-verify-by-manifest-not-by-executing-the-candidate`, guard-contract learnings in AGENTS (`cq-assert-anchor-not-bare-token`, vacuous-guard class).

### Related issues and PRs

#9307 (umbrella, stays open for PR 2 / PR 3), #9306 (PR 1, merged), #9375 (PR-A, merged `fdd690ea49`), #9409 (draft, overlapping files), #9400 (its issue), #9232 (duration-aware packing, closed),
#9402 / PR #9407 (quarantine of red checks; that PR also introduced `regenerate-shard-manifest.py --incremental`), #9324 / ADR-262 (path-gated batteries), #8800 (census sandbox shares inodes with the live repo; the recorder must use a detached worktree, see Open Code-Review Overlap).

## Problem Statement

1. The evidence that decided PR 1's 23 demotions is irreproducible (session-scratch inotify scripts), blind to queue overflow and to `stat`/missing-file probes, and was shown wrong once in four ratchet hits.
2. The pre-pass still costs ~123 s CPU per local `--affected` run on a loaded host; most of the remaining cost is the runner's own text being followed into 16 suites' closures (~475 edges each).
3. Three minting defects remain: subcommand forms (`deno test`, `make test`, `npm run test`, `bun run test`, `bash -c "cd x && bun test ..."`) can mint a repo-root `test/` edge; `REPO_ROOT="$(cd "$(dirname ...)/.." && pwd)"` loses `/..`; a deleted declared subject silently drops its edge.
4. The ratchet sees literal `knowledge-base/` strings one hop deep only.
5. `scripts/suite-shard-legs.tsv` was last fully regenerated before the ratchet existed; the ratchet is floor-weighted.

## Proposed Solution

### Phase 0 — Baselines before any edit (no code change)

- 0.1 Capture base streams at the branch point for both bench probes (`README.md`, and a multi-path probe of one script plus one legal doc): `bash scripts/test-all.sh --print-selection --paths=<probe> > $SCRATCH/base-<probe>.tsv`. The bench takes its base as a per-phase variable (`--base <rev>`): Phase 1 compares against the branch point, Phase 2 against the Phase 1 head, so the two selection deltas are never mixed.
- 0.2 Record the sandbox parity fingerprint: `bash scripts/test-all.sh --enumerate all`, filtered to the 8 keep-list labels, in stream order, plus the `SCRIPTS_SHARD=1/2` and `2/2` selected counts for the always-on kept label. **Re-capture it after every merge of `origin/main`**, not only at the branch point (a registration PR 9409 adds is a label the first capture never saw), and compare at the end of every phase (Verification gate V1).
- 0.3 `git fetch origin main`; `gh pr view 9409 --json state,mergeStateStatus,mergedAt`. If it merged, merge `origin/main` first and skip the Phase 1.5 `--incremental` fallback.
- 0.4 D1 census (decides whether D1 exists): independent of the runner, list suites whose text uses `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` (or `/..`-less variants) and name an existing repo file that is absent from their `--print-selection` edge set. Zero such suites -> D1 is dropped and the plan says so in ADR decision 18.
- 0.5 Recorder prototype gate (before any recorder code is committed): run the static probe scan (file tests, `stat`, `ls`, `find`) over the suite files of the 24 re-price candidates and count unresolvable operands. If more than five suites have an unresolvable probe operand, the static scan is the wrong mechanism: the verdict then relies on the conservative rule "any probe flagged, or unresolved, keeps the suite always-on" and the audit says the scan has low resolving power. The result is recorded in the audit doc either way.

### Phase 1 — PR-B: recorder first, then re-price, then breadth and minting

Order is rows-first (RED) inside each step; the recorder lands before anything that needs its verdicts.

- **1.1 B1 recorder `scripts/audit-suite-reads.sh` + `scripts/lib/inotify-open-recorder.py` + `scripts/audit-suite-reads.test.sh`** (kept thin; the Cut List removes the rest).

  *Event source: a committed ~60-line python3 raw-inotify reader, not `inotifywait`.* Measured at plan time on this host (`max_queued_events` 16384, `max_user_watches` 524288): `inotifywait -m -r -e open` (and also without `-e`) delivered exactly 16,384 events for 17,500 distinct file opens while the reader was stopped and printed **no** `Q_OVERFLOW` record on stdout or stderr, whereas a python3 `ctypes` reader on the same scenario received the kernel's `IN_Q_OVERFLOW` (mask `0x4000`) once (`events=16384 overflow=1`). `inotifywait` therefore cannot satisfy the plan's own "never demotable from an incomplete recording" property. The python reader also removes the `inotify-tools` dependency (the test can drive the real reader in CI), reports `IN_CREATE|IN_ISDIR` events so a directory created mid-suite is detected instead of silently unwatched, and prints `ready` after its initial watch walk (and `Failed to watch <dir>` per failure). Other measured facts the design relies on: sentinel file opens appear in the stream in order with the suite's opens (so windows are cut in event order, not by the one-second `%s` timestamp); `[[ -e missing ]]` produces no event (the stated blind spot); identical consecutive events are coalesced by the kernel (17,000 repeat opens of one file produced one event; irrelevant to which-files evidence).

  *Checkout and isolation (security review).* A `git worktree` shares `.git` with the live repo (refs, stash, config, hooks, object store); ~70 suites run `git stash|branch|tag|update-ref|config|gc|worktree|push|fetch|reset --hard`. The recorder therefore materialises the audited revision with `git archive <full-sha> | tar -x` into a `mktemp -d` (0700, `umask 077`, prefix `soleur-audit-reads.`, outside `.worktrees/` so the reapers leave it alone), then `git init` and one commit so suites that need a repository get a private one; the revision is resolved with `rev-parse --verify <rev>^{commit}`, must be an ancestor of the PR head or `origin/main`, and its full SHA is stamped into every row. Each suite runs from the checkout root via `"${argv[@]}"` only (never `eval` or `bash -c "$line"`), in its own `setsid` process group that is killed after the suite, under `env -i` with a scratch `HOME`, `TMPDIR`, `XDG_*` and `SOLEUR_SCRATCH_BASE`, a scratch `bin/` of symlinks to the resolved `bash git python3 node bun` plus the coreutils it needs as the **entire** PATH, and a network-less namespace (`unshare -rn`, or `bwrap --unshare-net`; the recorder refuses to start if neither exists). `--enumerate-commands` runs inside the same checkout and environment, so argv and the stamped revision come from one tree. After each suite `git status --porcelain --ignored` must be empty, else the suite is `unreliable` and the checkout is reset (`git clean -fdx && git checkout -- .`). Cleanup traps EXIT, INT, TERM and HUP; a startup sweep removes stale prefixed directories after asserting the path is under the mktemp root, non-empty and not a symlink. `--only <label>` rejects `..` and is never used as a path component.

  *Verdict integrity.* Event file and TSV live in a second 0700 directory outside the checkout. Window sentinels are `<nonce>-start-N` / `<nonce>-end-N` opens in a dedicated directory inside the watched tree, with a per-run random nonce; each must appear exactly once, in order; a malformed line, a missing sentinel or a dead reader after any suite makes the row `unreliable`. `record` refuses to start above `--max-load` (default 4.0 one-minute load average; the load average is printed in every row).

  *Verdict classes, one `verdict()` function* (live `record` and replayed `verdict` both call it; two modes). `demote` mode: `demotable` (all opens inside the cover, no flagged probe, rc 0, two identical recordings, within the audit's size caps: at most 8 second-level directories, 700 files, a cover of at most 14 edges), `uncovered` (reads outside the cover, listed), `disqualified` (a flagged probe in the suite file; a directory created during the suite; or a hit in the carried-disqualifier regex table over the suite file: git diff/log/show/rev-list/merge-base/status/ls-files/ls-tree, `origin/main`, `--changed`/`--base`, network, clock) and `unreliable` (`IN_Q_OVERFLOW` in the suite window or the following gap, `Failed to watch`, rc non-zero, cap hit (rc 124), load refusal, repeat disagreement, sentinel or contamination failure; **retry, never a change to the current classification**). `check` mode (Phase 2.2 only) has its own vocabulary: `covered` / `uncovered` / `unreliable`, never `demotable`, with the size caps and the carried disqualifiers reported as informational only (the 16 runner-reaching rows legitimately carry ~475 edges and their text names `origin/main` and `git diff`). Exit codes: 0 every row decided and none `unreliable`; 2 usage error; 3 at least one row `unreliable` (full table still written); 4 zero suites enumerated or zero windows. One cover source, `--cover-from-selection`: the anchored edges of the label from a `--print-selection --paths=README.md` run **in the audited checkout** (the effective edge set the gate really uses — declared plus derived — so the recorder never re-implements label-to-array resolution, which the runner and `scripts/lint-orphan-test-suites.sh` already do). A candidate demotion is audited by applying the proposed lib edit inside the checkout first, so its edges appear in that run. The cover is derived from static suite text, not from the observed reads, so the comparison is not tautological; a declared-only cover would be stricter and its false `uncovered` results would err toward re-promotion, the safe direction. Rows are appended per suite as they finish; `--only` re-runs one.

  *Named blind spots* (script header and audit): probes of missing files and `stat` (no open event), hardlinked or symlink-aliased reads (census issue #8800), coalesced repeat events, a sanitized environment (`env -i`, no network) that can change what a suite reads relative to a developer shell, and suites that need installed dependencies the fresh checkout lacks (rc non-zero, therefore `unreliable`, never a re-promotion). Customers: the 24 re-price rows, the Phase 2.2 rows and the Phase 2.5 batteries; the committed tool exists so any later demotion can reproduce its evidence, which is the standing rule in the lib's demotion block.
- **1.2 D3 subcommand forms.** Rows first in `scripts/test-affected-derive.test.sh`; then extend the skip list in `_affected_derive` to `deno test`, `make test`, `npm run test`, `bun run test`, `pnpm run test`, `yarn run test`, and apply the same skip inside the `-c` payload word loop (the loop currently mints `test` from `bash -c "cd x && bun test ..."`). The existing `case "$_prev $_tok"` sees two words, so the `npm|bun|pnpm|yarn run test` forms need a `"run test"` pattern, not three-word patterns. Mutation row m5 in `scripts/test-all-affected.test.sh` patches the exact skip-list line (`"bun test"|"npm test"|...`); extending that line breaks m5's anchor (rc 98), so m5 is edited in the same commit. Verified at plan time against `bash scripts/test-all.sh --enumerate-commands all` (551 records): no registration uses `deno test`, `make test`, `npm|bun|pnpm|yarn run test` (the one `-c` payload is `npm run test:ci`, a different token), so the stream stays byte-identical; the bench proves it.
- **1.3 D2 ratchet breadth.** Run the widened oracle against the 541 registrations and implement only the forms that surface at least one real uncovered suite today, from: `find knowledge-base`, `${KB_DIR:-knowledge-base}`, split-literal joins, `$PWD/knowledge-base`, suites with no code file in argv, and (only if the measurement shows hits) relevance-gated registrations and the non-KB declared edges of the demoted suites. Read forms live in one table in the oracle (one row per form). Forms that surface nothing are listed with counts in the file header as "still unseen". Re-baseline with `--write-baseline`; every baseline row this plan adds is classified in the audit doc (real read -> edge added, or scan false positive -> recorded). Rows that arrive from another PR are classified by that PR.
- **1.4 B3 re-price of the 23 existing demotions.** Run the recorder (`demote` mode, `--cover-from-selection` in the audited checkout) on the 23 demoted suites. `disqualified` or `uncovered` re-promotes that suite to `ALWAYS_ON_SUITES` (first adding the missing edge if the read is real and bounded) **and deletes its now-dormant `AFFECTED_*_PATHS` array in the same commit** (`always_on` wins in the classifier, but the census linter still validates the array); `unreliable` is retried up to twice on a quiet host and, if it stays unreliable, leaves the suite as it is and says so in the audit. Append "Round 2" to `always-on-audit.md`: one row per audited suite (verdict, rc, files, dirs, cover, load average, recorder revision) and the Phase 0.5 prototype result; the section states that it supersedes the "one audited run" caveat of ADR-242 decision 15. The floor `_MIN_ALWAYS_ON_DECLARED=116` and row f1 move **only if the count falls below 116**, and then together, in one commit, to the new count; they are never raised. **`scripts/domain-model-drift` (B2) is deliberately NOT decided here:** ADR-242 decision 15 attributes its 82 s derive cost to its test file's comment naming `test-all.sh`, the exact cost A5 removes, so measuring it before A5 is a wasted measurement; B2 is decided once, in Phase 2.6, after A5.
- **1.5 Register the recorder suite**: `run_suite "scripts/audit-suite-reads" bash scripts/audit-suite-reads.test.sh` appended **last** in the scripts block of `scripts/test-all.sh` (after any registration that exists there at that moment, including PR 9409's), with `AFFECTED_SCRIPTS_AUDIT_SUITE_READS_PATHS` placed at the end of the demotions block in the lib (not next to the array PR 9409 adds). The manifest row for the new label is produced by Phase 3; if Phase 3 is dropped or split off, run `python3 scripts/regenerate-shard-manifest.py --incremental --write` instead (add path; incumbent rows pinned verbatim).
- **1.6 D4 deleted declared subject (conditional, cut-first, last in Phase 1).** Implement only after 1.1-1.5 are green on CI. (a) Migrate 19 of the 22 slash-less declared directories (census one-liner: iterate `AFFECTED_*_PATHS` arrays and test `-d` without trailing `/`) to trailing slashes and make `scripts/lint-orphan-test-suites.sh` reject a slash-less existing directory (unit row in `scripts/lint-orphan-test-suites.test.sh`, not the mutations battery, whose `DECLARED_TOTAL` floors would force a re-tiling). The three entries that end in `/.` (`plugins/.`, `plugins/soleur/.`, `plugins/soleur/skills/.`) mint dead edges today (for example `^plugins/soleur/./`); they are **deleted, not migrated** (migrating would make them live and widen selection for two suites), and the removal is the one stream-visible change this step may show (no selection effect), listed in NFR-1's allowed diff. (b) Mint declared and consumed edges without the `-e` filter through a **second named mint function** (`_affected_add_declared_edge`; derived tokens keep `_affected_add_edge`) placed between `_affected_in_list()` and `_affected_add_edge()` so the m9/t11 extraction span (which ends at the first `^}` after `_affected_add_edge() {`) carries it, called from the two declared/consumed sites (`scripts/test-all.sh` ~2645 and ~2660), with an m9 twin pinning its own directory normalisation; a declared `dir/` entry is a directory edge, any other a file edge. (c) Update mutation m9 in `scripts/test-all-affected.test.sh` in the same commit. Selection delta on today's tree: none; the delta exists only for a future deletion, pinned by a fixture row. D4 reverses part of ADR-242 decision 12 (which deliberately drops an edge to a deleted path and names the census linter as the catch), so ADR decision 17 marks that clause superseded if D4 lands. Reverting D4 is a five-part set (slash migration, lint rule, `_affected_add_declared_edge`, m9 and its twin, fixture). If dropped, file one deferral issue (what, why, re-evaluate when a declared subject is next deleted) and say so in ADR decision 17.
- **1.7 ADR-242 decision 17** (see Architecture Decision); written last so it states whether D4 landed.

### Phase 2 — PR-C: runner leaf, heavy batteries, and (if evidenced) D1

Gate: Phase 1 is green on CI and its parity fingerprint is recorded before Phase 2 starts.

- **2.1 A5 runner leaf.** One named array in `scripts/lib/test-affected-paths.sh`, **`CLOSURE_LEAF_FILES`** (deliberately outside the `AFFECTED_` prefix so the census linter's edge-array scan at `scripts/lint-orphan-test-suites.sh` ~1134 does not treat it as an edge array; comment points at ADR-242 decision 18), lists exactly `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh`. `scripts/lib/test-relevance-paths.sh` is **not** a leaf: the `runner-changed` fallback greps the diff for only those two literals (`scripts/test-all.sh` ~2960-2961), so a diff touching the relevance lib would meet the narrowed pre-pass unchecked. A derive-suite row asserts the two fallback literals equal the array's members (they are coupled by name only, so the equality is pinned rather than assumed). In `_affected_file_edges_uncached`, for a leaf file only: keep pass 1 (real `source`/`.`/import edges) and skip passes 2 and 3 (invocation tokens and `$VAR/path` tokens the text merely names). The leaf comparison strips a leading `./` first (memo entries are keyed on the raw path and `./`-rooted edges stay unanchored, so `bash ./scripts/test-all.sh` would otherwise miss the match and double-memoise); a derive row covers `bash ./scripts/test-all.sh`. The file stays an edge of every closure that reaches it. Before the bench runs, verify the declared arrays are consumed through `_affected_resolve_edges` (re-added after `_affected_derive` resets the set, `scripts/test-all.sh` ~2672-2674), not through the token passes of the lib file, so skipping them does not drop a declared edge; the verification is a recorded command in the audit doc. A5 touches no `if/elif` ladder (learning 2026-09-29). Two fixture rows: a **branch-scope** diff containing a leaf file still reports `runner-changed` and runs everything (the fallback comes from the diff names, independent of edges); a **staged-scope** diff containing only a leaf file (where the `runner-changed` arm is dark by construction, #9173) selects every label that carried `^scripts/test-all.sh` before A5, because the file stays an edge and only the leaf's outbound edges are cut.
- **2.2 Recorder before bench acceptance (order matters; a blocking gate).** Run the recorder in `check` mode with `--cover-from-selection` on the (currently 16) derived rows whose closure reached the runner, in the post-A5 tree, **before** the bench result is accepted; the recorder result is the behavioural check and the bench is the textual one. The bench's textual removal test cannot tell a name from a runtime read (the runner reads `scripts/suite-shard-legs.tsv`, the durations table and `ci.yml` through `$VAR/path` tokens, and suites that execute the runner depend on them), so this recorder run is the only check for that class. A suite that reads a path outside its post-A5 edge set is a finding: fix by the narrowest declared edge for that suite — **each runtime-read data file found this way (for example `scripts/suite-shard-legs.tsv`, `ci.yml`) gets a CI-resident declared edge on the labels that read it, with a receipt** — or narrow the leaf rule; never accept the delta. The leaf set is not a safety argument by itself (the fallback fires when the diff touches the runner, while the cut edges matter when the diff touches a file the runner names); this recorder run plus those declared edges are.
- **2.3 Selection-delta mode in the bench.** `scripts/affected-prepass-bench.sh` gains one declared-delta compare (`--leaf-files <paths>`). Most of a runner-reaching row's ~475 edges are second-hop edges (a helper sourced by a suite the runner names), so "the path occurs literally in a leaf file" is the wrong test. An edge removal is **explained** iff every path by which that edge reached the label's base closure passes through a leaf file's outbound pass-2/3 edge; the bench computes the expected head set with its own independent walk (grep plus `source`/`.`-follow over the label's suite file and the leaf files, never the runner's derive or a runner-produced closure dump) and asserts head equals base minus that set. Any added edge, class change, label change or summary mismatch fails. A retained-real-edge check asserts every `source`/`.` target of the leaf files that resolves to an existing file is still present in every row that had it (population floor: at least one such target). A minimum-delta check asserts every affected label loses at least one edge (a neutralised leaf rule must not pass as certified). The mode is acceptance for this change; the PR records whether it stays committed (default: it stays, small, described in the bench header) so it does not rot unnoticed.
- **2.4 D1 `REPO_ROOT` idiom (only if the Phase 0.4 census found a missed edge; its own commit).** Resolve `$(cd "<dir>[/..]" && pwd[ -P])` to the cd target through `_affected_normpath` before the greedy `$(cd*pwd*)` replacements in `_affected_edge_token`. D1 widens, A5 narrows; they land as separate commits with separate stream diffs against separate bases. The added edges are classified by an independent grep-based resolver that is seeded with fixtures for `/..` depth, `-P` and quoting variants; on disagreement the resolver wins and the mismatch fails.
- **2.5 Phase C audit of the six heavy always-on batteries.** Default per suite is keep. A suite narrows only when (1) the recorder run is clean (no overflow, rc 0 on a quiet host, no probe outside the proposed cover, two agreeing recordings), (2) a perturbation run passes (edit a comment in ten unrelated tracked files and add then delete an unrelated file in a detached worktree: exit code and output hash unchanged), and (3) a corpus check over the last 60 first-parent commits lists the commits the suite would no longer be selected for, each classified as unable to change the verdict. Steps 2 and 3 are recorded command lines in the audit doc, not committed tooling. Expected: `scripts/test-all-infra-coverage-notice` is the only plausible narrowing; `scripts/test-contention`, `sentry-alert-live-fidelity`, `lint-orphan-test-suites` and `hook-input-classification-mutation` are keep with a one-line reason each (the last opens 16,636 files and is expected to be `unreliable` from queue overflow: it is recorded as such and kept, never fixed by raising limits); `operator-ack-guard` is decided on evidence. The three batteries ADR-262 already withdrew get one status line. CI is unaffected: the local gate declines nothing under `CI`.
- **2.6 B2 `scripts/domain-model-drift`, re-measure and floor.** Decide B2 here, after A5: measure its derive cost with `--print-selection` in the post-A5 tree; if small, run the recorder with the proposed demotion applied in the checkout and, if clean, remove it from `ALWAYS_ON_SUITES` and declare `plugins/soleur/scripts/domain-model-drift.sh`, `plugins/soleur/scripts/lib/domain-model-lib.sh`, `scripts/domain-model-drift.test.sh` and `scripts/lib/test-affected-paths.sh`; otherwise record the measured reason it stays. If suites left the set and the count fell below 116, move `_MIN_ALWAYS_ON_DECLARED` and f1 together to the new count; regenerate the ratchet baseline (`--write-baseline`); run the bench and report the measured CPU factor against the Phase 1 head stream.
- **2.7 ADR-242 decision 18.**

### Phase 3 — D5: regenerate the shard manifest (last commit, re-runnable)

Before starting: re-check PR 9409 (Phase 0.3 command), merge `origin/main`, and re-capture the parity fingerprint. If 9409 merged, its regeneration is superseded by this one.

- Select runs: `gh run list --workflow ci.yml --branch main --event push --status success -L 12 --json databaseId,headSha`; keep the five newest whose head SHA is on `origin/main` and satisfies `git merge-base --is-ancestor fdd690ea49 <headSha>` (post-PR-A).
- Download per run (so the inputs are explicit, replayable and event-filtered): `gh run download <id> -p 'suite-timings-scripts-[0-9]*' -D $SCRATCH/<id>` (directory named by run ID; the generator stamps provenance from directory basenames and reads `<dir>/*/suite-timings.tsv`), then `python3 scripts/regenerate-shard-manifest.py --timings-dir $SCRATCH/<id1> ... --timings-dir $SCRATCH/<id5> --write` (the paired `scripts/suite-durations.tsv` is written by the same call). The `--runs 5` form selects "the five newest at call time" without an event filter and tolerates a run with no artifacts, so it is not used. Paste the generator's per-run timed-label counts into the PR body (all five non-zero) and the ten largest per-label deltas against the incumbent table; a label that moves by more than 5x is investigated before committing (the `ms` field is unbounded in the generator).
- Read the predicted leg table before committing. If the worst leg is a single suite longer than the ~10-minute ceiling (PR 9409's own regeneration measured `scripts/test-all-affected` at 791.5 s), that is an atomic-suite bottleneck K cannot fix (learning 2026-09-25): record it, file the heavy-group move as its own issue, and link it in the PR body. The heavy manifest is not regenerated (3 suites, out of the brief).
- Lag, stated: the five runs predate PR-B/PR-C, so the ratchet's weight is measured at its post-PR-A walk cost, which A5 then lowers; the manifest is conservative for that one suite, and the architecture review recommends a post-merge data PR as the cleaner home for D5. An optional refresh after merge is cheap (re-run the same procedure) and is the first thing to do if the ratchet's leg turns out to be the worst leg.
- Reproducibility: the replay recipe in the PR body is the five run IDs (directory names, also in the `generated-from-runs` header) plus the download and generator commands above; re-running them against the same IDs reproduces the pair.

### Phase 4 — Verification (see Acceptance Criteria)

Re-run the bench against the per-phase base streams, the parity fingerprint comparison, the targeted suites, and `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Revert matrix

Phases are commit-isolated but not free-standing. Reverting 1.4 or 2.6 must also revert or re-run the floor commit if one exists; reverting A5 must also revert the 2.6 `scripts/domain-model-drift` demotion (its cost argument depends on A5); reverting D4 is its five-part set; reverting 1.5 requires the Phase 3 manifest to be re-run (keys==registrations); reverting Phase 1 invalidates the Phase 2 base stream (Phase 2's bench base is the Phase 1 head by design); Phase 3 is always re-run last, never reverted by hand.

## Technical Considerations

### Merge-conflict plan against PR 9409

PR 9409 (`feat-one-shot-9400-prepush-ratchet-lane`; open, marked ready for review on 2026-10-02, mergeability UNKNOWN at plan time, so it can land at any point) edits `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`, `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` and `scripts/test-affected-kb-consumers.baseline.txt`. This plan does **not** duplicate its scope (the pre-push lane, `lefthook.yml`, `scripts/hooks/pre-push`, `plugins/soleur/skills/ship/SKILL.md`).

| Shared file | 9409 hunk | This plan's hunk | Resolution rule |
|---|---|---|---|
| `scripts/test-all.sh` | `run_suite "scripts/pre-push-ratchet-lane"` appended after `scripts/test-affected-derive` | `run_suite "scripts/audit-suite-reads"` appended last in the same block; D3/D4/D1/A5 edits inside `_affected_*` | add/add at the block tail: keep both, ours after theirs; the derive hunks are far from it; re-capture the parity fingerprint after the merge |
| `scripts/lib/test-affected-paths.sh` | `AFFECTED_SCRIPTS_PRE_PUSH_RATCHET_LANE_PATHS` between the DERIVE array and the "ALWAYS-ON AUDIT DEMOTIONS" comment | demotion arrays, `CLOSURE_LEAF_FILES`, `AFFECTED_SCRIPTS_AUDIT_SUITE_READS_PATHS` at the end of the demotions block, (conditional) 22 slash migrations | non-adjacent by construction |
| `scripts/test-affected-kb-consumers.baseline.txt` | two `scripts/pre-push-ratchet-lane` rows | rows from D2 | generated: after any merge run `bash scripts/test-affected-kb-consumers.test.sh --write-baseline`, never hand-merge |
| `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` | full `--runs 5` regeneration from pre-PR-A runs plus one new floor row | Phase 3 regeneration from post-PR-A runs (or, if Phase 3 is split off, the Phase 1.5 `--incremental` row) | generated: on conflict discard both sides and re-run the generator (ADR-235); whichever PR merges second owns the re-run |
| `scripts/test-affected-derive.test.sh`, `scripts/test-all-affected.test.sh` | none expected (9409 declares edges for its own suite in the lib, not in these files) | derive rows (D3, A5, D1), f1 and m9 edits | AC-P3 is re-run after every rebase; a hand-resolved conflict must not widen the `test-all-affected.test.sh` diff beyond f1/m9 |

If 9409 merges first, merge `origin/main`, re-register the recorder suite after its line, re-capture the fingerprint and let Phase 3 re-run on top (its regeneration is superseded by newer runs); if this PR merges first, 9409 re-runs its generator. Neither needs a hand merge. Baseline rows that arrive from 9409 are classified by 9409; this plan's audit table lists only its own rows.

### The shard-parity class (must not recur)

Rules for every edit in this PR: (1) no new label is added to the `scripts/test-all-affected.test.sh` sandbox keep-list and none is removed or reordered in the runner's enumerate stream; (2) `scripts/lint-dual-lockfile` stays in `ALWAYS_ON_SUITES`; (3) new registrations go last in their block (after any registration already there, including 9409's), and reach the manifest through the Phase 3 regeneration (or `--incremental` if Phase 3 is split off); (4) after each phase the Phase 0.2 fingerprint is identical and rows s1/s2 of `bash scripts/test-all-affected.test.sh` pass (the battery runs on this PR's CI because the diff touches the runner). Demoting or narrowing a suite changes which suites are *selected*, never the enumerate order, so Phases 1.4 and 2.5 are outside the class unless they touch `lint-dual-lockfile`. A new non-kept label (such as 9409's lane suite) cannot affect the sandbox, which trims the stream to the keep-list before the shard ordinal ticks; the fingerprint is nevertheless re-captured after every merge of `origin/main` to prove it.

### Other constraints

- A change to `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh` degrades the local `--affected` gate to the full battery (`runner-changed`); verification therefore uses targeted suite invocations plus the bench, and CI is the full gate (ADR-242 decision 1/3/4).
- Selection-direction asymmetry (ADR-242 decision 12): anchored edges err toward not running when diff text does not present a path as its own line; every narrowing in this plan is certified by the recorder and bench, every widening (D1, D4) by fixture rows.
- Bash 3.2 compatibility of the runner (no associative arrays, no `+=` on arrays beyond what exists); the recorder script targets bash 5 on the operator host but must not use features the repo's shell lint rejects.
- Recorder is operator tooling: it runs a private `git archive` checkout under `env -i` with a scratch `HOME`, scratch PATH and no network or credential variables, takes no runner lock (ADR-133), and never runs in CI.
- `max_user_watches` and `max_queued_events` are host properties the reader checks at startup; the recorder exits non-zero with `verdict=unreliable` rows, writes the full table anyway, and never reports `demotable` from a partial recording. An overflow marks the suite window and the following gap unreliable (the kernel emits one `Q_OVERFLOW` and drops events until the queue drains).
- Floor semantics: `_MIN_ALWAYS_ON_DECLARED` stays 116 (count today 119) unless the count falls below it; f1 pins the literal. A rebase that drops the count under the floor shows up as a mass `below-floor` refusal (exit 4) on the next local `--affected` run, so the f1 failure message and the PR body name that case.

### Verification gates (checklists over existing tests, not new guards)

- **V1 shard-leg parity.** The Phase 0.2 fingerprint is identical at the end of every phase and after every merge of `origin/main`; rows s1/s2 of `bash scripts/test-all-affected.test.sh` pass; `scripts/lint-dual-lockfile` is in `ALWAYS_ON_SUITES`; the sandbox keep-list `case` is unchanged. An empty fingerprint file fails the comparison (never "0 compared").
- **V2 manifest.** The manifest tables exactly the registered labels with no empty leg (`plugins/soleur/test/scripts-shard-manifest.test.sh`), and the pair of TSVs is generator output; replay is header-only plus `--timings-dir`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "PR-B (re-price the demotions with a recorder)" [brief] | Phase 1 (1.1-1.7); definition from issue 9307 comment: B1, B2, B3, D2, D3, D4 | mapped |
| 2 | "PR-C (runner leaf and the heavy batteries)" [brief] | Phase 2 (2.1-2.7); definition from issue 9307 comment: A5, D1 (evidence-gated), Phase C | mapped |
| 3 | "regenerating scripts/suite-shard-legs.tsv from at least five CI runs" [brief] | Phase 3 | mapped |
| 4 | "PR 2 and PR 3 of the series are untouched and out of scope" [brief] | Non-goals; no file of PR 2/PR 3 appears in Files lists | mapped |
| 5 | "plan for merge-conflict risk, do not duplicate its scope" [brief, about PR 9409] | Technical Considerations merge table | mapped |
| 6 | "the plan must not reintroduce that class" [brief, about the keep-list parity regression] | Technical Considerations parity rules; Verification gate V1; AC-P1..AC-P3 | mapped |
| 7 | "Define \"PR-B\" and \"PR-C\" from the relevant plans ... if the definitions are ambiguous, state your interpretation in Decisions" [brief] | Overview definition paragraph; Research Reconciliation row 1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/audit-suite-reads.sh` and its test (Files to Create) | "re-price the demotions with a recorder" | asked |
| D2 ratchet breadth, D3 subcommand forms, D4 declared subject (inside PR-B) | "PR-B (re-price the demotions with a recorder)" read through the issue 9307 definition of PR-B | asked (by definition) |
| D4 | "PR-B" via issue 9307 definition | asked (by definition; flagged cut-first) |
| A5 runner leaf (inside PR-C) | "PR-C (runner leaf and the heavy batteries)" | asked |
| D1 `REPO_ROOT` idiom (inside PR-C, evidence-gated) | "PR-C (runner leaf and the heavy batteries)" read through the issue 9307 definition | asked (by definition; dropped if the Phase 0.4 census finds nothing) |
| Phase C audit of the six heavy batteries | "the heavy batteries" | asked |
| Phase 3 regeneration of `scripts/suite-shard-legs.tsv` and its paired `scripts/suite-durations.tsv` | "regenerating scripts/suite-shard-legs.tsv from at least five CI runs" | asked (the paired table is written by the same generator call) |
| Declared-delta mode in `scripts/affected-prepass-bench.sh` | "runner leaf" | inferred — justification: A5 is not identity-preserving, and without a removed-edge compare the bench (the acceptance contract for any pre-pass change, ADR-242 decision 16) can only report a failure |
| ADR-242 amendment (decisions 17 and 18) | "PR-C (runner leaf and the heavy batteries)" | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; decision 12 is reversed in part and ADR-242 already forward-references decision 18 |
| `_MIN_ALWAYS_ON_DECLARED` / row f1 move (only if the count falls below 116) | "re-price the demotions" | inferred — justification: the floor and its pin must move together or the census guard rots |
| Decision-challenges record | "Define \"PR-B\" and \"PR-C\" ... state your interpretation" | inferred — justification: the split recommendation below is overridden by the brief and must stay challengeable |
| Parity fingerprint (Phase 0.2) | "the plan must not reintroduce that class" | asked |

### Split Assessment

- Subsystems touched: 2 — `scripts` (runner, lib, recorder, bench, TSVs), `knowledge-base` (ADR, audit doc, specs); `plugins/soleur/test/` suites are run, not edited
- Planned files: 13 edit + 5 create = 18 | Estimated changed lines: ~1,070 after the review-panel trims (recorder 220 + test 250, oracle 100, derive rows 120, lib 60, runner 70, bench 60, ADR 60, audit 80, generated TSVs ~50)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — PR-B (+ D5 optional) | PR-C at the Phase 1/Phase 2 seam. **Proceeding as a single PR** because the brief names all three pieces and the phases are commit-isolated and individually revertable; the override is recorded in `decision-challenges.md` and the cut order is D4, Phase C narrowing, A5.

## User-Brand Impact

- **If this lands broken, the user experiences:** a maintainer sees a green local `--affected` gate while a regression exists, and finds it at the CI full battery instead; or the local gate runs more suites than needed. No end-user-facing artifact changes: this is repository test tooling, and CI's full battery stays the authoritative merge gate.
- **If this leaks, the user's data is exposed via:** not applicable — the recorder reads repository files in a scratch worktree under `env -i` with no credential variables and writes TSV to a scratch directory; no user data or secrets are read or emitted.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern`, because the narrowing affects only the local pre-ship gate (CI declines nothing) and every narrowing needs recorder evidence plus a bench-certified delta.

*Scope-out override:* `threshold: none, reason: the diff touches scripts/test tooling and knowledge-base docs only; no auth, schema, API route, payment or user-data path, and CI's full battery remains the merge gate.`

## Observability

Operator tooling with no runtime surface; the section records how a maintainer sees the gate's health without SSH.

```yaml
liveness_signal:
  what:            per-suite AUDIT_READS receipts on stdout from the recorder; the dropped-consumer ratchet and the recorder test suite run in the CI test-scripts matrix on every push
  cadence:         per recorder invocation; per CI run for the suites
  alert_target:    a red CI check on the PR / main (the existing test-scripts matrix legs)
  configured_in:   scripts/audit-suite-reads.sh, scripts/test-all.sh (run_suite registration), .github/workflows/ci.yml (unchanged)

error_reporting:
  destination:     stderr plus a non-zero exit with a named code; no Sentry (local tool)
  fail_loud:       "AUDIT_READS ... verdict=unreliable reason=<q_overflow|watch_failed|rc|probe>" and exit 2; the verdict is never demotable on an incomplete recording

failure_modes:
  - mode:          inotify queue overflow or failed watch makes a recording incomplete
    detection:     Q_OVERFLOW event in the window or "Failed to watch" on stderr, both fatal in verdict()
    alert_route:   non-zero exit of the recorder; audit doc row marked unreliable
  - mode:          a narrowed suite stops running locally for a diff that matters
    detection:     bench declared-delta compare (removed edges must be explained) and the ratchet's population join
    alert_route:   red scripts/test-affected-kb-consumers, scripts/test-affected-derive and the bench exit code
  - mode:          registration or demotion shifts shard legs
    detection:     scripts/test-all-affected.test.sh rows s1/s2 and scripts-shard-manifest keys==registrations
    alert_route:   red CI test-scripts legs

logs:
  where:           stdout of the recorder (redirect to the scratch directory); CI job logs for the suites
  retention:       GitHub Actions default for CI logs; recorder output is kept in the audit doc Round 2 table

discoverability_test:
  command:         bash scripts/audit-suite-reads.sh --help
  expected_output: usage
```

## Guard Contract

Four guards. The shard-manifest and shard-parity checks are verification gates V1/V2 over existing tests (Technical Considerations), not new guards. Every RED row below asserts the exit code **and** a message substring (a crash must not read as RED), and every guard has a population floor so "0 checked" cannot pass.

### Guard 1 — recorder verdict function (`scripts/audit-suite-reads.test.sh`, B1)

**Property.** A suite is never reported demotable from an incomplete or unstable recording, a non-zero exit, a flagged probe, or reads outside its cover.

**Assembly.** Every verdict flows through the single `verdict()` function in `scripts/audit-suite-reads.sh`; its inputs are the event stream from `scripts/lib/inotify-open-recorder.py` (opens, `IN_Q_OVERFLOW`, `IN_CREATE|IN_ISDIR`, malformed lines), the reader's stderr (`ready`, `Failed to watch`), the suite rc, the cover (declared arrays or selection edges), the load refusal, the regex table and probe scan over the suite file, the contamination check, and the second recording. Live `record` and replayed `verdict` call the same function; the test drives `verdict` with synthesized streams and drives the **real** reader and `record` path on a fixture directory (the python reader needs no `inotify-tools`, so CI runs these arms).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | replayed stream containing `IN_Q_OVERFLOW` inside a suite window, and a second one only in the following gap | `unreliable` (rc 3, table written); never `demotable` |
| 1b | live arm: SIGSTOP the real reader, open (sysctl `max_queued_events` + 1000) distinct fixture files, SIGCONT | the real reader reports overflow; row `unreliable` |
| 2 | reader stderr containing `Failed to watch` before the first window | every suite `unreliable` |
| 3 | fixture suite that tests `[[ -e some/missing/path ]]` outside the cover | `disqualified` |
| 4 | a second fixture suite that probes after a compliant first suite | `disqualified` (every suite is scanned, not the first) |
| 5 | zero suites enumerated, and separately zero windows | exit 4 with a distinct message (not usage exit 2) |
| 6 | a suite that reads one path outside its cover and nothing else | exactly `uncovered`, path listed |
| 7 | suite exits non-zero (and a separate fixture that exits 124) | each exactly `unreliable` |
| 8 | two recordings of one suite disagree on the opened set | exactly `unreliable` |
| 9 | one fixture per entry of the carried-disqualifier regex table (loop over the table; floor: at least 8 entries) | each `disqualified`; deleting a table entry reds its own fixture |
| 10 | size caps: 9 second-level directories; 701 files; a cover of 15 edges | each `uncovered`/`disqualified` per the cap, exactly one class per fixture |
| 11 | same oversized reads/cover in `check` mode | no cap applied: `covered`; vocabulary is covered/uncovered/unreliable, never `demotable` |
| 12 | load above `--max-load` | refusal, rows `unreliable` |
| 13 | a suite that creates a directory under the checkout | `disqualified` |
| 14 | two back-to-back sub-second fixture suites | each suite's events land in its own sentinel window; a missing or duplicated sentinel makes the row `unreliable` |
| 15 | the cover is read from the audited checkout, not the operator's live tree (mutate the live tree after extraction) | verdict unchanged |
| 16 | harness: remove the `verdict` call from `record`, leaving replay only | the real-reader arm goes RED (verdict never produced) |
| 17 | must-PASS, non-canonical: a suite whose reads are a strict subset of a differently ordered cover and whose only file tests are on that cover | `demotable` |

**Anchor.** The recorder stamps the audited full SHA into every row and derives the cover (`--print-selection`) from that same extracted checkout, so one commit cannot move the cover and the recorded reads independently.

### Guard 2 — ratchet breadth (`scripts/test-affected-kb-consumers.test.sh`, D2)

**Property.** Every registered suite that reads a real `knowledge-base/` path through any form in the oracle's form table is always-on or carries a covering edge.

**Assembly.** Population stays derived: `--enumerate-commands --paths=README.md all` joined with `--print-selection --paths=README.md`; one form table in the oracle is the chokepoint every form flows through (a new form is one row). The matrix is **conditional on the forms Phase 1.3 implements**: rows 1-3 are written per implemented form, not for the whole candidate list.

**Mutation matrix** (each fixture row runs against a `/dev/null` baseline so the baseline cannot absorb it; mutations act on a scratch copy of the oracle with a landed check `count==1` and rc discrimination):

| # | Mutation | Expected |
|---|---|---|
| 1 | fixture suite reads `find knowledge-base` with no covering edge (if that form is implemented) | RED |
| 2 | the same for each other implemented form, one row each added after a compliant first | RED each |
| 3 | fixture suite with no code file in argv that reads a covered KB path | PASS covered; RED with the edge removed |
| 4 | empty enumeration / empty join (regression row beside the existing empty-enumeration row) | RED (population floor) |
| 5 | harness: drop one form row from the table in the scratch copy | its fixture row goes RED |
| 6 | every baseline row added by this plan carries a classification marker (real read / scan false positive) | an unclassified row reds the test (machine-checked, not prose in the audit doc) |
| 7 | must-PASS, non-canonical: a read written with different quoting that the form table lists, covered | PASS |

**Anchor.** The baseline is regenerated by the oracle (`--write-baseline`) and the test fails on stale and new rows alike; classification markers make a newly implemented form unable to turn green merely by being baselined.

### Guard 3 — runner-leaf selection-delta oracle (`scripts/affected-prepass-bench.sh` + `scripts/test-affected-derive.test.sh`, A5)

**Property.** After A5 the only differences from the base selection stream are removed edges that exist solely because a leaf file's text names them; no class change, no label change, no summary drift, no real `source` edge lost, and every affected label loses at least one edge.

**Assembly.** The bench's compare path is the single chokepoint for base and head streams. The removal explanation is computed by an **independent resolver** that the bench owns (an edge removal is explained iff every path by which it reached the label's base closure passes through a leaf file's outbound pass-2/3 edge; computed by grep plus a `source`/`.`-follow walk over the suite file and the files given by `--leaf-files`; it never calls the runner's derive and never reads a runner-produced closure dump), so the oracle is not the system under test. The leaf rule has one site in `_affected_file_edges_uncached`, driven by the one `CLOSURE_LEAF_FILES` array. Rows split into **stream rows** (synthesized streams through `--compare-only`, fast, CI) and **live rows** (a scratch `git archive` copy of the repo whose runner or lib array is mutated, then the live bench; operator-host, heavy, receipts recorded in the PR body).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | live: leaf rule also skips pass 1 (drops a real `source` edge such as `plugins/soleur/scripts/lib/proc.sh`) | bench rc 1, message names the retained-edge check; the retained-edge population floor is at least 1 |
| 2 | live: add a non-leaf file to `CLOSURE_LEAF_FILES` in the scratch copy | bench rc 1: a removed edge reachable by a path that avoids the leaf's outbound edges |
| 3 | stream: head drops a whole label or changes a class | rc 1 |
| 4 | stream: empty stream or summary mismatch | rc 1 (floor: at least one compared row) |
| 5 | stream: two removed edges, the second unexplained, after a compliant first | rc 1 (every removal is checked) |
| 6 | live: staged-scope diff containing only a leaf file | selects exactly the labels that carried `^scripts/test-all.sh` before A5 (pinned, not a disjunction); and a branch-scope row where the fallback comes from the diff names |
| 6b | derive row: `bash ./scripts/test-all.sh` as a suite argv; and the fallback literals vs `CLOSURE_LEAF_FILES` equality | leaf match survives the `./` form; any literal/array drift reds |
| 7 | live: neutralise the leaf rule so head equals base | rc 1 from the minimum-delta check (each affected label must lose at least one edge) |
| 8 | stream, must-PASS non-canonical: a removed edge explained by the index leaf (`scripts/lib/test-affected-paths.sh`) rather than the runner | rc 0 |

The recorder `check` run of Phase 2.2 is an acceptance step with a receipt (it catches a runtime-read data file such as `scripts/suite-shard-legs.tsv` that only the leaf's `$VAR/path` token named); it is not a mutation row because it cannot run in CI.

**Anchor.** The base stream is captured from the Phase 1 head, outside Phase 2's edits, so one diff cannot move both sides of the compare. When D1 lands it adds its own rows (independent-resolver disagreement fails) and its own base.

### Guard 4 — declared-edge minting and census (`scripts/test-all-affected.test.sh` + `scripts/lint-orphan-test-suites.test.sh`, D4; conditional with D4)

**Property.** A deleted declared subject still selects its suite, and no declared existing directory lacks a trailing slash.

**Assembly.** The new `_affected_add_declared_edge` (placed between `_affected_in_list()` and `_affected_add_edge()` so the m9/t11 extraction span carries it), its two call sites in `_affected_derive`/`_affected_classify` (`scripts/test-all.sh` ~2645 and ~2660), and the census linter's declared-path check; every declared array flows through the lib and the linter.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | end-to-end: a declared path is deleted in a diff; the suite must be selected | selected (RED if the `-e` filter is restored) |
| 2 | dispatch: swap either call site back to `_affected_add_edge` | the end-to-end row goes RED |
| 3 | a declared existing directory without trailing slash | census unit row RED, exit code and message asserted |
| 4 | a second slash-less directory after a compliant first | RED (every entry is checked) |
| 5 | the census scan finds zero declared arrays | RED |
| 6 | m9 twin for the new function: drop its directory normalisation | RED with a landed check (the existing m9 keeps covering `_affected_add_edge`) |
| 7 | must-PASS, non-canonical: a declared file path that does not exist and is not a directory | mints a file edge; PASS (this is also the positive control for row 1) |

**Anchor.** The 22-entry list (19 migrated, 3 deleted) is committed in the audit doc; reverting the lib while keeping the linter rule is caught by the linter.

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` through `soleur:architecture` with one `## Amendment — 2026-10-02` of two short decisions, inserted **before** `## References` so decisions 16, 17 and 18 stay contiguous (numbers follow landing order and match the ADR's existing forward reference to "decision 18" for the runner leaf):

- **Decision 17 (PR-B):** the recorder's verdict contract — a recording that overflowed, failed to watch, exited non-zero or disagrees with its repeat is never evidence for a demotion, and a probe the open-event stream cannot see disqualifies a suite; the always-on audit's observed-reads evidence is re-issued as "Round 2" with the recorder revision and states that it supersedes decision 15's "one audited run" caveat; the recorder's event source is a raw-inotify reader because `inotifywait` was measured to drop `IN_Q_OVERFLOW` silently; D3 subcommand forms are not operands (one sentence). **If D4 lands:** declared and consumed edges are minted without the existence filter (reversing the clause of decision 12 that drops an edge to a deleted path; derived tokens keep the filter) and slash-less declared directories are rejected by the census. **If D4 is dropped:** the decision says so and cites the deferral issue.
- **Decision 18 (PR-C):** the runner and its index (`CLOSURE_LEAF_FILES`) are closure leaves for text mentions (passes 2 and 3 only), with the selection delta recorded by the bench (measured CPU factor, removed-edge count by label) and the Phase C outcome table (one line per heavy battery). Decision 18 also amends decision 16's wording that the bench is the identity contract: it remains so for every non-narrowing change, and A5 is the declared, bench-certified exception. **If D1 lands:** the `REPO_ROOT` idiom resolution (a widening) is recorded here with its census; **if the census found nothing,** the decision says D1 was dropped and why.

Both are PR deliverables, not follow-up issues. Next-free ordinal check is not needed (amendment, not a new ADR).

### C4 views

None change. To be confirmed by `soleur:work` reading all three of `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` in full: actors and systems involved are the repository's test runner, a local developer shell and the CI test jobs (already modeled as CI edges); external human actors added: none; external systems or vendors added: none (the recorder makes no network call); containers or data stores: none; actor-to-surface access relationships: none change. The cited green run is `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Sequencing

Nothing is soak-gated; the amendment describes the landed state.

## Acceptance Criteria

### Functional Requirements

- [x] **AC-B1** `scripts/audit-suite-reads.sh` exists with `record`, `verdict`, `--cover-from-selection`, `--only`, `--max-load`, `--help`, with the committed reader `scripts/lib/inotify-open-recorder.py`; `bash scripts/audit-suite-reads.test.sh` exits 0 with every Guard 1 row driven, including the live-reader overflow arm that runs in CI (impl: `verdict()` in `scripts/audit-suite-reads.sh`; test: `scripts/audit-suite-reads.test.sh`); the script header names the blind spots (probes of missing files, directories created mid-run, window-boundary events, `env -i`).
- [x] **AC-B2** The Round 2 table in `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md` has one row for each of the 23 demoted suites plus `scripts/domain-model-drift` (verdict, rc, files, dirs, cover, load average, recorder revision) and the Phase 0.5 prototype result (count of unresolvable probe operands). `unreliable` rows state the retry count and are left unchanged; `disqualified` rows are re-promoted in `scripts/lib/test-affected-paths.sh`. — Round 2 table (23 rows) in always-on-audit.md; the `scripts/domain-model-drift` row is in Round 3 (decided after the leaf rule)
- [x] **AC-B3 (decided in Phase 2.6, after A5)** `scripts/domain-model-drift` is either removed from `ALWAYS_ON_SUITES` in `scripts/lib/test-affected-paths.sh` with its three declared paths plus `scripts/lib/test-affected-paths.sh` (the census requires every `AFFECTED_*_PATHS` array to contain the lib path, as it will for `AFFECTED_SCRIPTS_AUDIT_SUITE_READS_PATHS`), or the audit records the measured derive cost (command output cited) that keeps it. — stays always-on on the recorder rule; derive cost 0.2 s post-leaf (82 s in Round 1)
- [x] **AC-D3** `scripts/test-affected-derive.test.sh` has rows for `deno test`, `make test`, `npm run test`, `bun run test` and a `bash -c "cd x && bun test ..."` payload; none mints `^test/`; impl in `_affected_derive` of `scripts/test-all.sh` (skip list and `-c` word loop).
- [x] **AC-D2** `bash scripts/test-affected-kb-consumers.test.sh` exits 0; the form table is committed; each implemented form has a fixture row; the header lists still-unseen forms with counts; every baseline row added by this plan is classified in the audit doc.
- [x] **AC-D4 (conditional on D4)** Of the 22 slash-less declared directories, 19 carry trailing slashes and the three `/.` entries are deleted; `scripts/lint-orphan-test-suites.sh` rejects a slash-less existing directory (unit row in `scripts/lint-orphan-test-suites.test.sh`); a fixture row shows a deleted declared subject still selects; m9 in `scripts/test-all-affected.test.sh` is updated. If D4 is dropped: one deferral issue exists and ADR decision 17 cites it. — dropped: #9441 filed, ADR decision 17 cites it
- [x] **AC-C1** Runner leaf: `CLOSURE_LEAF_FILES` in `scripts/lib/test-affected-paths.sh` lists exactly `scripts/test-all.sh` and `scripts/lib/test-affected-paths.sh` and equals the `runner-changed` fallback literals (pinned by a derive row); `_affected_file_edges_uncached` skips passes 2 and 3 only for those; two fixture rows (branch-scope and staged-scope diff containing a leaf file) pass; the recorder ran with `--cover-from-selection` on every derived row that reached the runner **before** the bench result was accepted; `bash scripts/affected-prepass-bench.sh --base <phase-1-head> --runs 3` (declared-delta mode) exits 0 on both probes; every runtime-read data file the recorder found has a CI-resident declared edge (receipt in the PR body); the PR body and ADR decision 18 cite measured median CPU before and after, the load average, and the removed-edge count by label. — bench exit 0 on both probes (2.2x and 2.3x); recorder check run done first; leaf also keeps `source "$VAR"` and dirname-sourced loads
- [x] **AC-C2 (conditional on the Phase 0.4 census)** D1: a derive-suite row proves `REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"` resolves to the repo root, with added edges classified by the independent resolver (resolver wins on disagreement); D1 is its own commit with its own base stream, and the selected-count delta on the multi-path probe is reported and bounded in the PR body (a fleet-wide widening must be visible). If the census found nothing, ADR decision 18 records D1 as dropped. — census 91 to 29 missing pairs; delta 48 rows / 329 edges / 0 class changes
- [x] **AC-C3** Phase C: the audit doc has one decision line for each of the six remaining heavy always-on batteries, the three evidence results for any narrowed suite, a one-line reason for every keep, and a status line for the three ADR-262-withdrawn batteries; `${#ALWAYS_ON_SUITES[@]}` is reported before and after. — all six keep; always-on 120 to 139
- [x] **AC-D5** `scripts/suite-shard-legs.tsv` header lists five `generated-from-runs` IDs (the directory names passed to `--timings-dir`), each a green main `push` `ci.yml` run on `origin/main` whose head contains `fdd690ea49`; the PR body pastes the download and generator commands, the generator's per-run timed-label counts (all five non-zero), the ten largest per-label deltas against the incumbent table (none above 5x unexplained) and the predicted per-leg totals; `scripts/test-affected-kb-consumers` is `src=measured` in `scripts/suite-durations.tsv`; the worst predicted leg is at or under the ceiling, or an issue for the atomic-suite move is filed and linked in the PR body. — worst predicted leg 664.9 s (total work, not an atomic suite; legs balanced to 27 s)
- [x] **AC-ADR** ADR-242 carries decisions 17 and 18 with the selection deltas and measured figures; `bash plugins/soleur/test/c4-count-parity.test.sh` is green.

### Parity class (AC-P)

- [x] **AC-P1** The Phase 0.2 fingerprint (enumerate order of the 8 keep-list labels, and the s1/s2 selected counts) is identical at the end of each phase and after every merge of `origin/main`; the comparison output is pasted in the PR body.
- [x] **AC-P2** `bash scripts/test-all-affected.test.sh` passes rows f1, m9, s1, s2 (and the whole battery) on the final tree; `scripts/lint-dual-lockfile` is still in `ALWAYS_ON_SUITES`.
- [x] **AC-P3** `git diff origin/main -- scripts/test-all-affected.test.sh` contains no addition to the sandbox keep-list `case` and no change to `SCRIPTS_SHARD` rows other than the floor pin (if it moved), m5 (D3) and m9 (if D4 lands); re-checked after every rebase. — only row u (victim moved after D1) and mutation m5 changed

### Non-Functional Requirements

- [x] **NFR-1** Selection for the two bench probes after Phase 1 differs from the branch-point streams only by the listed re-promotions and demotions and, if D4 lands, the removal of the three dead `/.` edges (empty diff if none).
- [x] **NFR-2** ShellCheck is clean on every changed shell file; bash 3.2 syntax in the runner and lib is preserved (`bash -n`, and the derive suite's 3.2 arms where available).
- [x] **NFR-3** No registration moves an existing suite's leg: `git diff origin/main -- scripts/suite-shard-legs.tsv` outside Phase 3 contains only added rows.

### Quality Gates (targeted suites; the full affected battery degrades to full because the runner is touched)

`bash scripts/audit-suite-reads.test.sh`, `bash scripts/test-affected-derive.test.sh`, `bash scripts/test-affected-kb-consumers.test.sh`, `bash scripts/lint-orphan-test-suites.test.sh`, `bash scripts/test-all-affected.test.sh`, `bash plugins/soleur/test/scripts-shard-manifest.test.sh`, `bash plugins/soleur/test/regenerate-shard-manifest.test.sh`, `bash scripts/test-all-pr-battery-gate.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`; then the merge-gate full battery on CI.

### Post-merge (tracked, not blocking)

- Comment on umbrella #9307 with the outcome of PR-B / PR-C / D5 and the still-open PR 2 / PR 3 (net issue flow 0; new issues only for the D4 deferral, if D4 is dropped, and the Phase 3 atomic-suite move, if it applies).

## Test Scenarios

- Given a replayed event stream with `Q_OVERFLOW` in a suite window, when `verdict` runs, then the suite is `unreliable` and never `demotable` (Guard 1 row 1).
- Given a suite that tests `[[ -e docs/missing.md ]]` outside its cover, when audited, then it is `disqualified` (Guard 1 row 3).
- Given the fixture registration `bun test src/a.test.ts` and `bash -c "cd app && deno test"`, when the derive runs, then no `^test/` edge is minted (AC-D3).
- Given a declared edge to a path that is then deleted (D4 only), when a diff deletes it, then the suite is selected (AC-D4).
- Given the post-A5 tree, when the README probe runs, then the (re-measured) runner-reaching rows lose only edges the bench's independent walk explains through the two leaf files' outbound pass-2/3 edges, every affected row loses at least one edge, and every row keeps its real `source` edges (AC-C1).
- Given the five recorded run IDs, when their artifacts are re-downloaded and the generator re-run with one `--timings-dir` per run, then the manifest pair is reproduced (AC-D5).
- Regression: the sandbox rows s1/s2 each report `ran>=1` after every phase (AC-P2).

**Integration verification (for `soleur:qa`):** `bash scripts/test-all.sh --print-selection --paths=README.md | tail -1` prints `AFFECTED_SUMMARY ... fallback=none`; `bash scripts/audit-suite-reads.sh --help` prints usage.

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Recorder runs under machine load and suites time out (five suites failed under the PR 1 recorder at load 40-58) | high | `--max-load` refusal, load average printed per row; a timeout/rc is `unreliable` (retry, never a re-promotion on host noise); only `disqualified`/`uncovered` re-promote |
| `inotifywait` silently drops `IN_Q_OVERFLOW` (measured: 16,384 events delivered for 17,500 opens, no record) | certain if used | the recorder's event source is a committed python3 raw-inotify reader that sees the overflow (measured: `overflow=1`) |
| Queue overflow on the suite that opens 16,636 files; the kernel drops later events after one `Q_OVERFLOW` | medium | the suite window and the following gap are `unreliable`; the table is still written in full and the exit is non-zero; that suite stays always-on |
| Static probe scan cannot resolve most `$VAR` operands, so the recorder answers "keep" for nearly everything | medium | Phase 0.5 prototype gate counts unresolvable operands first; more than five -> the conservative rule is stated as the mechanism and the audit says the scan has low resolving power |
| A5 drops an edge a suite really needs | medium | pass 1 retained; recorder on every affected row with `--cover-from-selection` before bench acceptance; bench retained-real-edge check; the leaf set is exactly the two files the `runner-changed` fallback already covers; staged-scope fixture row |
| D4 reverses decision 12 for deleted paths and widens selection unexpectedly | low | no missing declared path today (census); fixture row for the future case |
| PR 9409 (open, ready for review) merges first and conflicts on generated files | high | regeneration rule: re-run the generator, never hand-merge; Phase 3 is the last commit; Phase 0.3 and Phase 3 re-check its state; fingerprint re-captured after the merge |
| Regeneration exposes an atomic suite above the ~10 minute ceiling (`scripts/test-all-affected` measured 791.5 s by 9409's regen) | medium | read the predicted leg table first; file the heavy-group move separately (learning 2026-09-25) |
| Floor moves weaken the "index gutted" guard, or a rebase drops the count under it | low | the floor changes only if the count falls below 116, never rises, and f1 moves in the same commit; f1's failure message names the rebase case |
| A suite run by the recorder mutates the live repo (a `git worktree` shares `.git`, refs, stash, config and hooks; ~70 suites run mutating git commands) or reads credentials | medium | private `git archive` checkout with its own `git init`, `env -i`, scratch `bin/` PATH, network-less namespace, per-suite process group; see Phase 1.1 |
| Parity class recurrence | low | Verification gate V1: fingerprint at every phase and after every merge of `origin/main`, s1/s2 on this PR's CI, keep-list `case` unchanged (AC-P3) |
| The recorder's `env -i` run reads differently from a developer shell, or a suite needs installed dependencies a fresh worktree lacks (rc non-zero, so `unreliable`) | medium | stated as a named limitation; verdicts are evidence for the recorded run only, CI's full battery stays authoritative |
| Operator host lacks python3 inotify support (non-Linux, or `ctypes` unable to load libc) | low | the recorder refuses to start with exit 2 and a named message; it is Linux-only operator tooling and never runs in CI beyond its own test |

Out of scope: PR 2, PR 3, the heavy manifest (`scripts/suite-shard-legs-heavy.tsv`, 3 suites), the pre-push lane, the memo-index lever PR-A did not take.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Repository test tooling and CI manifest; no product, legal, finance, marketing, sales, operations or support implication. The brainstorm-recommended specialists list is empty (no brainstorm preceded this plan). The CTO lens (blast radius of a narrowed local gate with CI authoritative; generated-file merge discipline with a concurrent draft PR; the shard-parity class) is carried by the Technical Considerations and Guard Contract sections and by the plan-review panel.

No Product/UX Gate: no path under `components/`, `app/**/page.tsx` or `app/**/layout.tsx` appears in the Files lists (mechanical UI-surface override checked).

## Open Code-Review Overlap

- #8659 (`scripts/test-all.sh`: 33 suites replace test-helpers' EXIT trap and leak the incident sandbox on direct runs) — **acknowledge**: unrelated concern (trap hygiene in suites); not folded in.
- #7942 (`scripts/test-all.sh`: two `*.mutation.sh` batteries run in no gate) — **acknowledge**: different class (orphan registration); the census linter owns it.
- #8800 (`scripts/lib/test-affected-paths.sh`, `scripts/test-all-affected`: census sandbox shares inodes/symlinks with the live repo) — **acknowledge**, with a design constraint taken from it: the recorder audits a private `git archive` extraction with its own `git init` (not a symlink or hardlink sandbox, and not a `git worktree`, which shares `.git`), so its writes cannot reach the live repo.

## Files to Edit

- `scripts/test-all.sh` — D3 skip list (`"run test"`, `deno test`, `make test`) and `-c` loop, (D4 only) `_affected_add_declared_edge`, (D1 only) `_affected_edge_token`, A5 leaf in `_affected_file_edges_uncached`, `_MIN_ALWAYS_ON_DECLARED` (only if the count falls below 116), one `run_suite` appended last in the scripts block.
- `scripts/lib/test-affected-paths.sh` — demotion arrays (`domain-model-drift`, any Phase C narrowing, any re-promotion), `CLOSURE_LEAF_FILES`, `AFFECTED_SCRIPTS_AUDIT_SUITE_READS_PATHS` (each new array contains the lib path itself), `ALWAYS_ON_SUITES` edits, and (D4 only) 19 trailing-slash migrations plus deletion of the three `/.` entries.
- `scripts/test-affected-kb-consumers.test.sh` and `scripts/test-affected-kb-consumers.baseline.txt` — D2.
- `scripts/test-affected-derive.test.sh` — D3, D1, A5, D4 rows.
- `scripts/test-all-affected.test.sh` — mutation m5 (D3 skip-list anchor), row f1 (only if the floor moves), mutation m9 (only if D4 lands); no keep-list or `SCRIPTS_SHARD` row change.
- `scripts/lint-orphan-test-suites.sh` and `scripts/lint-orphan-test-suites.test.sh` — slash-less declared directory rule (unit row only).
- `scripts/affected-prepass-bench.sh` — declared-delta (removed-edge) compare mode.
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` — generated (Phase 3 `--timings-dir` x5; Phase 1.5 `--incremental` only if Phase 3 is split off).
- `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md` — Round 2.
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` — amendment, decisions 17 and 18.

## Files to Create

- `scripts/audit-suite-reads.sh`
- `scripts/lib/inotify-open-recorder.py`
- `scripts/audit-suite-reads.test.sh`
- `knowledge-base/project/specs/feat-one-shot-shard-legs-reprice-recorder-runner-leaf/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-shard-legs-reprice-recorder-runner-leaf/decision-challenges.md`

Path-glob check: every path above matches a tracked file (`git ls-files`) except the four Create entries, which are new by definition.

## Success Metrics

- Pre-pass CPU on the README probe: median of 3 interleaved runs, base vs head, via `scripts/affected-prepass-bench.sh`; reported with load average. Target is stated after measurement, not asserted (baseline today: user 102.5 s + sys 20.5 s at load 12.6).
- Always-on census: `${#ALWAYS_ON_SUITES[@]}` before 119, after = reported; always-on suite seconds (awk over `scripts/suite-durations.tsv`) before 1,146.6.
- Light test-scripts legs: predicted per-leg totals from the regeneration; worst leg named.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or carries filler text fails `deepen-plan` Phase 4.6; this one declares `none` with a reason.
- Every figure quoted from issue 9307 or the PR-A plan (18 suites, 23 README edges, 39.3 minutes, four Phase C candidates, 0.3 s derive cost) was found stale or unverifiable at plan time; the work phase must re-measure before citing any of them in an AC, ADR or commit message.
- Moving `_MIN_ALWAYS_ON_DECLARED` without moving row f1 (or the reverse) turns the census guard into a no-op or a red; they move in one commit.
- `scripts/lint-orphan-test-suites-mutations-{a,b}` carry `DECLARED_TOTAL` floors and `--rows` tiling; add the D4 census row to `scripts/lint-orphan-test-suites.test.sh`, not to the mutation battery.
- The recorder's attribution is by time window; a stray background process of the operator's shell writes into the window. Run on a quiet host and treat any event under the scratch worktree's `.git` or from a non-suite PID as a reason to re-run (events carry no PID; the `env -i` scratch `HOME` keeps shell-startup reads out).
- Regenerate, never hand-edit, `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv`; a conflict with PR 9409 is resolved by re-running the generator.
- `--print-selection` takes about two minutes of CPU at load; run the bench and baselines in the background and read results from files, not from a foreground wait.

## References & Research

- Issue 9307 (umbrella; last two comments carry the scope); PR-A plan (archived) `knowledge-base/project/plans/archive/20261002-033030-2026-10-01-feat-cheap-affected-prepass-and-pr1-residuals-plan.md`
- ADR-242 (decisions 12-16), ADR-240 (checked-in shard assignment), ADR-262 (path-gated batteries), ADR-133 (no runner lock), ADR-183
- `knowledge-base/project/specs/feat-affected-parallel-test-gate/always-on-audit.md`, `edge-anchoring-corpus.md`
- Commits `abd29f4bcf`, `ed804aecff` (parity regression and fix-forward), PR 9220; PR 9375 (`fdd690ea49`); PR 9409
- Plans named in the brief: `2026-09-23-feat-ci-test-shard-speedup-phase-2-plan.md`, `2026-09-25-feat-ci-test-scripts-sharding-plan.md`, `2026-09-26-feat-ci-orphan-suite-rows-split-plan.md`, `2026-09-24-chore-retire-ci-leg-durations-8006-plan.md`, `2026-09-29-ci-duration-aware-shard-packing-plan.md` (shard mechanics; none defines PR-B / PR-C)
