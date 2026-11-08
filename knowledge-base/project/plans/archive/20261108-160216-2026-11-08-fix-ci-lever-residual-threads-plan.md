---
title: "fix: CI-lever residual threads — battery-gate probe convergence + replay job-name allowlist"
date: 2026-11-08
slug: ci-lever-residual-threads
branch: feat-one-shot-12360-ci-lever-threads
issue: 12360
---

## Overview

Two decoupled CI-lever residual threads shipped as one PR. Thread 1 (#12360): the #9323 soak probe `scripts/followthroughs/pr-battery-gate-saving-9323.sh` cannot reach a verdict — its serial GitHub-API read volume (~13 artifact reads per qualifying run, ~3 per examined candidate) exceeds even the `PBG_UNBOUNDED=1` operator seam (~11 min measured 2026-11-07), and its escape arm's `pending` state absorbs permanently on open PRs (an open PR's `merge_commit_sha` is a test-merge sha that can never carry a `push` run). Fix: bounded-parallel API reads across the examine/artifact/escape phases plus re-scoping `pending` to merged-PR outcomes only — preserving the 0/1/2/3/78 exit vocabulary and the `SOLEUR_FT_EARLIEST` sweeper refusal. Thread 2 (#9729 schedule arm, operator decision 2026-11-08): the stage-4 go/no-go re-ruling failed criterion (a) on the worst-case bound (19.38% ≥ 12%), inflated by 29 `unclassified-job` units — pre-#12089-umbrella job names (`rule-body-lint`, `adr-ordinals`, `grok-fidelity`, `harness-discovery`) and the CLA posted names (`cla-check`/`cla-evidence`) absent from `scripts/ci-pr-affected-replay.py`'s classification sets. Fix: add a pinned historical/folded-name classification set so refused-run classification routes those names as non-suite jobs instead of `not-evaluable`. Stage 4 stays non-activated: `CI_PR_AFFECTED` unset, `PR_AFFECTED_LOCKED` intact, `merge_group` keeps the full battery; the third R3 ruling pass on a fresh window is explicitly out of scope.

## Research Insights

### Premise Validation (Phase 0.6)

- **Issues:** #12360 OPEN (type/bug, no closing PR), #9729 OPEN (SCHEDULE decision recorded 2026-11-08 on the issue), #9323 OPEN (the soak this probe serves), #12089 CLOSED — merged as commit `bb3c83b9bf` / PR #12250 (the 16→3 umbrella fold, landed 2026-11-07, mid-way through the measured ejection window 2026-10-28..2026-11-07). All cited issues verified live via `gh issue view`.
- **Files:** `scripts/followthroughs/pr-battery-gate-saving-9323.sh` (319 lines) and `scripts/ci-pr-affected-replay.py` (2645 lines) both exist on `origin/main` and HEAD — fix plans, not build plans.
- **PR #12377** (`feat-one-shot-10862-norun-investigation`, OPEN, not draft) edits `scripts/ci-pr-affected-replay.py` at docstring/`ci_runs`/`cmd_collect`/`main` hunks (-38, -417/+420, -620/+674, -2624/+2679) and `plugins/soleur/test/ci-pr-affected-replay.test.sh` at fixture-helper hunks (~74, ~185-222, ~330-343, ~3484, ~4298) — confirmed DISJOINT from the classification sets (~:199-233), `suites_failed_in` (:471-496) and `classify` (:510-549). Merge-order rebase handles it; whichever lands second reconciles the fake-gh fixture-key scoping that PR's test changes introduce.
- **Collision precheck:** `collision-precheck.sh 12360` → hit PR #12412 — this pipeline's OWN auto-created draft on this branch (not a foreign duplicate). `9729` → clean.
- **ADR corpus (Phase 0.6 item 4):** ADR-262 R1 pins "an escape is caught on the push run, not the PR" — consistent with re-scoping `pending` to merged-PR outcomes; the escape arm still reads push runs. ADR-032's 2026-11-06 amendment is the canonical folded-member table (3 required umbrellas: `guards-ruleset` ci.yml ×8 members, `quality-guards` pr-quality-guards.yml ×4, `secret-guards` secret-scan.yml ×5; advisory folds `guards-advisory` ×3, `quality-advisory` ×8+). ADR-276's amendment ledger records both NO-GO re-rulings; no ADR contradicts bounded-parallel API reads or a second classification set.

### Property List (Phase 0.6b)

- **T1-P1** A sweep of the probe completes its read phases within an operator-reasonable wall (target: the sweeper's 300 s kill; hard requirement: `PBG_UNBOUNDED=1` converges without structural NOT-YET).
- **T1-P2** `pending > 0` no longer absorbs on open PRs — a qualifying set containing open PRs but no missing merged-PR push runs reaches a verdict.
- **T1-P3** Exit vocabulary (0 PASS / 1 FAIL / 2 NOT YET / 3 CANNOT ESTABLISH / 78 xtrace refusal), the `SOLEUR_FT_EARLIEST` sweeper refusal, `PBG_BUDGET_S≤300` validation, `ART_READ_CAP`/`EXAMINE_CAP`/`PAGE_CAP`/`MAX_RUNS`/`MIN_RUNS` bounds and the quota-preflight floor are all preserved.
- **T2-P1** Refused-run classification no longer drops post-#12089 names (`rule-body-lint`, `adr-ordinals`, `grok-fidelity`, `harness-discovery`, `sandbox-canary-capture-gate`, `plugin-root-propagation-gate`, `tc-document-sha-guard`, `marketplace-manifest-guard`, `service-role-allowlist-gate`, `credential-path-guard`, `lockfile-sync` + folded names in the other umbrella workflows + `cla-check`/`cla-evidence`) into `not-evaluable` — they route as non-suite jobs (the `always-run-job` class) → `rule-irrelevant`.
- **T2-P2** A genuinely unknown job name still lands `not-evaluable` (the honesty contract: "an unreadable or unclassified unit is never 'no failure'").
- **T2-P3** The new set is machine-pinned to its authority files (member tokens in the umbrella workflows' aggregate steps; CLA names in `scripts/required-checks.txt`) so future folds/unfolds force an update — never a silent drift.
- **NON-ACT** `CI_PR_AFFECTED` stays unset, `PR_AFFECTED_LOCKED` intact, `merge_group` keeps the full battery; `.github/workflows/*.yml`, `scripts/ci-pr-selection.sh`, `scripts/required-checks.txt` (content), the ruleset and all infra files untouched.

### Cut List (Phase 0.6b)

- **Resumable progress across invocations (issue's "and/or" arm)** → buys T1-P1 → deferred, not built: bounded-parallel reads are the cheaper mechanism for the same property (measured basis below), and durable probe state across sweeps has no substrate — the sweeper runs probes under `env -i` on ephemeral runners with a `timeout` kill; a state file would need a GHA-cache/artifact channel the sweeper contract does not define. Trigger to revisit: a parallel implementation that still starves inside `PBG_BUDGET_S≤300`.
- **Early-exit the artifact loop once `evidenced ≥ MIN_RUNS`** → buys T1-P1 partially → cut: with parallel reads the remaining reads are ~free, and shrinking the evidenced set degrades the mean's quality for no wall gain.
- **Re-run the R3 ruling / activate S4 in this PR** → explicitly out of scope per operator schedule terms (fresh-window ruling happens later, once the queue-cancel rate settles).
- **A cancelled-run policy for `unsettled-jobs`** → the issue's schedule term names ONLY the allowlist update; unsettled legs on cancelled runs stay `not-evaluable` (honest — the suite genuinely did not report).

### Value Measurement (Phase 0.6c)

- **T1 measured basis (the probe run the issue cites):** ~11 min wall under `PBG_UNBOUNDED=1` for `qualifying_runs=40 evidenced_runs=21 candidates_examined=73 pages=6` — ≈600+ serial `gh api` reads (6 list + ≤219 examine + ~286 artifact + ~80 escape). At bounded concurrency 8 the same read count projects to ~90-150 s — inside the sweeper's 300 s kill (`FT_PROBE_TIMEOUT`, `scripts/sweep-followthroughs.sh:66`). Command that produced the number: `PBG_UNBOUNDED=1 bash scripts/followthroughs/pr-battery-gate-saving-9323.sh` (local run, output posted on #9323, 2026-11-07).
- **T2 measured basis:** the 2026-11-07 R3 record (`receipts/go-no-go.md`, `replay-summary.txt`): 29 `unclassified-job` units of the 61-unit worst-case numerator → bound 19.38% ≥ 12% vs the recorded counterfactual 32/382 → 11.09% < 12%. Computed with `python3 -I scripts/ci-pr-affected-replay.py verdict`.

### Repo Research (sequential-fallback — repo-research-analyst role run inline)

- **Probe structure** (`pr-battery-gate-saving-9323.sh`): serial phases — quota preflight (1 read) → gate-PR read (1) → paginated runs list (≤6 pages) → examine loop (≤EXAMINE_CAP=220 candidates × ≤3 reads: `pulls?head=`, `pulls/N/files`, `runs/N/jobs`) → artifact phase (≤MAX_RUNS=40 runs × [1 listing + ≤~12 zip downloads]) → escape loop (≤40 PRs × 2 reads: `pulls/N`, `workflows/ci.yml/runs?event=push&head_sha=`). One deadline contract `api()`/`api_bin()` caps each call at `min(60, END-SECONDS-5)`; rc 46 = budget cut → `cut_ny` (exit 2). `SECONDS`/`END` math is shell-global — a `&` worker subshell must not rely on inheriting a live `SECONDS` (epoch-based `END` via `date +%s` is the unambiguous form).
- **Escape arm** (`:291-310`): three PR states — closed+`merged_at` null → `dropped`; empty sha → `pending`; sha set → push-run read (`failure|timed_out|startup_failure|action_required` → ESCAPE; `success` → ok; else `pending`). An OPEN PR's `merge_commit_sha` is the API-reported TEST-merge sha (verified on #11038) — non-null, so open PRs take the sha path, find no push run, and land in `pending` permanently. `pending > 0` → exit 2.
- **Pending re-scope shape:** `state=="open"` is readable off the same `pulls/N` read the arm already makes (`meta` carries `state`/`merged_at`) — an open bucket needs no extra read; the discriminator is `state`, not `merge_commit_sha` (the test-merge sha is set for open and closed-unmerged alike).
- **Replay classification** (`ci-pr-affected-replay.py`): `ALWAYS_RUN_JOBS` frozenset (:199-213) + `SUITE_JOB` regex (:196) are the two pin sets; `suites_failed_in` (:471-496) marks a failing non-suite job `unclassified-job`→`ne`→`not-evaluable` unless its name (split on `" ("`) is in `ALWAYS_RUN_JOBS`. Parity: `plugins/soleur/test/ci-pr-affected-replay.test.sh:646` asserts `sorted(ALWAYS_RUN_JOBS ∪ {4 suite families}) == sorted(ci.yml job keys)` exactly — so historical names CANNOT go into `ALWAYS_RUN_JOBS`; a separate frozenset is required.
- **Folded-name authority:** umbrella member names are enumerable as `member <name>` tokens in each umbrella job's "Aggregate member verdicts" step — 11 tokens in `ci.yml`, 14 in `pr-quality-guards.yml`, 5 in `secret-scan.yml` (30 total), matching ADR-032's amendment table. `cla-check`/`cla-evidence` are CLA Required ruleset contexts (posted check-runs via `merge-queue-cla-synthetics.yml`), enumerated in `scripts/required-checks.txt`'s CLA section and `scripts/ci-required-ruleset-canonical-required-status-checks.json`.
- **Merge-group surface:** 7 workflows trigger `merge_group:` (apply-sentry-infra, ci, merge-queue-cla-synthetics, pr-quality-guards, secret-scan, tenant-integration, vendor-pin-verify) — a refused ci.yml queue run's job listing can surface other workflows' job/check names via the shared merge_group check suite (mechanism for the `cla-check`/`cla-evidence` appearances; job names of those workflows are a wider version of the same drift class — see decision-challenges row).
- **Test surfaces:** `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` (297 lines, fake-`gh` fixture per `$FX/*.json`, 50-assertion floor, `d2` row currently pins open-PR→pending — the exact row the fix inverts) and `plugins/soleur/test/ci-pr-affected-replay.test.sh` (~4400 lines, mutant battery; `row_unclassified`+`mystery-job` row at :526/:3460 pins T2-P2; `mutate unclassified-job-reassuring` at :3569 pins the classification branch).
- **Sweeper contract** (`scripts/sweep-followthroughs.sh`): probes run by direct exec under `env -i` with only declared/forwards names (`SOLEUR_FT_EARLIEST` is the sweeper channel marker); `FT_PROBE_TIMEOUT=300` is the per-probe kill. A new env knob on the probe (e.g. concurrency) needs no sweeper change ONLY if it carries a sane default — the sweeper does not forward arbitrary env.
- **Registration:** probe is enrolled via the `<!-- soleur:followthrough script=… earliest=2026-10-09T00:00:00Z secrets=GH_TOKEN -->` directive on #9323; its suite leg is registered in `scripts/test-all.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` (no new registration needed — the same files keep their names).

### Institutional Learnings (sequential-fallback — learnings-researcher role run inline)

- `learnings/2026-07-20-the-fix-for-an-evidence-discarding-gate-discarded-its-evidence.md` — **worker telemetry goes to FILES, never `$( )` capture.** Directly governs the parallelization shape: each `&` worker writes its result row to a `$WORK/` file; the parent aggregates by reading files. A `run_saved="$(worker)"` capture would swallow the worker's status stream and reintroduce the class this learning names.
- `learnings/2026-07-15-widening-a-guard-to-accept-a-future-mechanism-is-a-fail-open-unless-self-validating.md` — a widened allowlist must self-validate: the new classification set needs a parity pin to its authority (member tokens / required-checks), or a future fold/unfold silently re-opens `not-evaluable` drift — this is why T2-P3 exists.
- `learnings/2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` — the guard/probe must pin the property it names, not a neighbour: the pending fix pins "merged-PR push run", not "any absent run".
- `learnings/logic-errors/2026-10-05-closed-set-exit-5-...md` — the sweeper execs probes under `env -i`; suites must drive the probe the way the sweeper does; new exit semantics need sweeper-path rows, not just fixture rows.
- `learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` — `--arg` is not forwarded through `gh --jq`; use two-stage `--json` + standalone `jq --arg` (applied to the code-review overlap query below).
- `learnings/2026-09-11-a-filer-with-no-honest-exit-takes-the-free-one-at-any-price.md` — the population a mechanism acts on is whoever its enforcing mechanism reaches; the pending set is every qualifying PR, so the re-scope is defined over `state`, not over the sha heuristic.
- `learnings/workflow-issues/2026-10-02-early-exit-pipe-consumers-sigpipe-under-pipefail.md` — early-exit consumers under `pipefail` SIGPIPE producers; applies to any `| head`-style read bound introduced in worker plumbing.
- Constitution notes applied: `set -uo pipefail` discipline (the probe already runs without `-e` — worker functions must return codes explicitly), `jq ... // empty`, `gh api --paginate` needs `jq -s 'add // []'`, snake_case/`local` vars, operator-protection signals on stdout, code comments cite symbol anchors not line numbers.

### Related Issues / PRs

- #12360 (thread 1), #9729 (thread 2, SCHEDULE 2026-11-08), #9323 (parent soak), #12089/#12250 (umbrella fold), #10448 (retire-vs-schedule, now resolved SCHEDULE), #10862/PR #12377 (adjacent norun hardening — disjoint hunks), #5780/#9454 (merge-queue CLA synthetics origin), #11038 (test-merge sha evidence), #12283 (`workflow-yaml-strict` member added 2026-11-07 — member set still moving).
- Prior plan context: `knowledge-base/project/plans/2026-10-12-feat-ci-pr-affected-only-gating-plan.md`, spec `knowledge-base/project/specs/feat-ci-path-filtering/`, runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`, receipts `knowledge-base/project/specs/archive/20261108-080602-feat-one-shot-ci-lever-residuals/receipts/`.

## Enhancement Summary

**Deepened on:** 2026-11-08
**Coverage:** `sequential-fallback` — plugin subagents are unavailable on this harness surface; every prescribed agent/skill role (research, learnings, spec-flow, cto, review lenses) ran inline sequentially with the same definitions.
**Gates verified (deepen-plan §4.x):** 4.6 user-brand PASS (threshold `none`, no sensitive-path files); 4.7 observability PASS (5 fields, `grep`-verb discoverability command, literal `observability-ok`); 4.8 PAT sweep PASS (0 hits); 4.9 non-UI skip; 4.10 no-store skip; 4.11 Guard Contract lint green (1 entry, 5-row matrix); 4.12 Scope Check pass (one unfenced section, all rows mapped/justified); 4.13 no new autonomous surface; 4.5 fired lexically on `unreachable`/`timeout` — false positive (verdict reachability + wall-budget words, no network-connectivity hypothesis).
**Halt-gate result:** all pass; no halts.

### Key Improvements (deepen pass)

1. **Precedent-diff (§4.4):** the bounded-parallel pool is NOT novel — `scripts/test-all.sh` `_pj_fill`/`_pj_reap`/`wait -n -p` (~:2196-2411) is the in-repo canonical form, including its bash≥5.1 serial-degrade gate (:2230); atomic result-file writes mirror the replay tool's own `.part` + `os.replace` pattern (`fail_suites`, ~:455). No new precedent class created.
2. **Verify-the-negative (§4.45):** the plan's load-bearing negatives verified live — "open PR's merge_commit_sha can never carry a `push` run" (test-merge sha semantics, evidenced on #11038 per the script header); "member names cannot go in `ALWAYS_RUN_JOBS`" (the `:646` parity row asserts exact equality with ci.yml job keys — read directly); "`FOLDED_JOBS ∩ ALWAYS_RUN = ∅`" (the two name sets enumerated: 11 member tokens vs 17 always-run names + 4 suite families — disjoint).
3. **Post-edit self-audit:** no dropped/renamed symbols — every plan-prescribed name (`FOLDED_JOBS`, `PBG_JOBS`, `open` bucket, `cut`/`fail`/`qual`/`skip` worker row vocabulary) is new-introduced, not a reference to removed machinery; pre-existing names (`cut_ny`, `fail_api`, `api`, `api_bin`, `green_prs`, `green_ids`, `run_partial`, `evidence_absent`, `ART_READ_CAP`, `EXAMINE_CAP`, `MAX_RUNS`, `MIN_RUNS`, `PAGE_CAP`, `SETTLED`, `SUITE_JOB`, `ALWAYS_RUN_JOBS`, `suites_failed_in`, `failing_jobs`, `classify`, `member`) each verified at their cited locations by direct read during research.
4. **Cited-issue verification:** #12360, #9729, #9323, #12089, #12377 states + bodies read live via `gh`; fold commit `bb3c83b9bf` and its job-removal diff verified via `git show`; the 30 `member` tokens re-extracted from the three umbrella workflow files; `cla-check`/`cla-evidence` confirmed at `scripts/required-checks.txt:273-274`.
5. **PR #12377 adjacency:** diff hunks enumerated and confirmed disjoint (its edits: docstring/`ci_runs`/`cmd_collect`/`main` + test fixture-key helpers; ours: `ALWAYS_RUN_JOBS` region + `suites_failed_in` + parity rows). Rebase-order note carried into tasks.md 3.4.

### New Considerations Discovered

- The merge_group census (`receipts/census-w2.txt` STEM rows) empirically bounds which names reach a ci.yml run's job listing — the basis for the 13-name `FOLDED_JOBS` default rather than the wider 30-member or all-merge_group-workflows sets (decision-challenges row 5).
- bash `( )`/`&` subshells share the parent's `SECONDS` epoch (verified locally 2026-11-08) — the `api()`/`api_bin()` `END-SECONDS-5` deadline contract is worker-safe unchanged; a `bash -c`/`xargs -P` child restarts `SECONDS` and would silently break it (one reason the pool is `&`-based).
- Pending-ruling rows for the parent's batched technical-ruling CTO live in `knowledge-base/project/specs/feat-one-shot-12360-ci-lever-threads/decision-challenges.md` (8 rows; one operator-ruled scope row, seven `pending - assumed:` technical rows).

## Problem Statement / Motivation

**Thread 1 (#12360).** `scripts/followthroughs/pr-battery-gate-saving-9323.sh` cannot produce a verdict — not inside the sweeper's 300 s per-probe kill, and not even under the `PBG_UNBOUNDED=1` operator seam (~11 min wall measured 2026-11-07: `qualifying_runs=40 evidenced_runs=21 candidates_examined=73 pages=6`). Two stacked causes: (a) ~600+ serial `gh api` reads exceed any sweep-sized wall; (b) the escape arm's `pending` bucket is absorbing — an open PR's `merge_commit_sha` is a test-merge sha that can never carry a `push` run, so at ~30 open PRs of repo volume `pending > 0` is near-permanent and `NOT YET` never clears. Until it clears, #9323's measurement arm cannot close.

**Thread 2 (#9729, operator SCHEDULE 2026-11-08).** The stage-4 go/no-go re-ruling failed criterion (a) on the worst-case bound (19.38% ≥ 12%). 29 of the 61 worst-case numerator units are `unclassified-job` — refused queue runs whose only failing jobs were names absent from the replay tool's classification sets after the #12089 umbrella fold: `rule-body-lint` ×20, `adr-ordinals` ×4, `grok-fidelity`/`harness-discovery` ×4, `cla-check`/`cla-evidence` ×1. The recorded counterfactual — those 29 routed as `rule-irrelevant` — bounds at 11.09% < 12%.

## Proposed Solution

**T1.** Restructure the probe's read phases around a bounded-parallel worker pool (`&` subshells + `wait -n -p` reaping — the proven in-repo idiom at `scripts/test-all.sh` `_pj_fill`/`_pj_reap` ~:2196-2411, with a bash≥5.1 serial fallback mirroring its `_pj_say_serial` gate at :2230) whose workers write per-unit result FILES under `$WORK/` that the parent aggregates in candidate order. Deadline/quota semantics are unchanged: `api()`/`api_bin()` keep the `min(60, END-SECONDS-5)` per-call cap (bash `( )`/`&` subshells share the parent's `SECONDS` epoch — verified 2026-11-08), rc 46 still means "wall deadline spent" and funnels to `cut_ny`. Separately, re-scope `pending` in the escape arm to merged-PR outcomes only: `state=="open"` moves to a new `open` bucket (mirroring `dropped`), because an open PR's absence of a merge-commit push run is expected, not missing evidence.

**T2.** Add a second classification frozenset to `scripts/ci-pr-affected-replay.py` — `FOLDED_JOBS` — consulted at the same point as `ALWAYS_RUN_JOBS` in `suites_failed_in` (`name.split(" (")[0] in ALWAYS_RUN_JOBS or in FOLDED_JOBS`), carrying exactly the 11 ci.yml umbrella member tokens + `cla-check` + `cla-evidence` (13 names). A matching row classifies the job as a non-suite `folded-job` (never `unclassified-job`, never `ne`), so a refused run failing only folded names lands `rule-irrelevant`. New parity rows pin the set to the `member <name>` tokens extracted from `.github/workflows/ci.yml`'s aggregate steps and to the two `cla-*` lines of `scripts/required-checks.txt`.

## Files to Edit

| File | Change |
|---|---|
| `scripts/followthroughs/pr-battery-gate-saving-9323.sh` | Bounded-parallel read phases (runs pages, examine loop, artifact phase, escape loop); new `PBG_JOBS` env knob (default 8, clamp 1-16); `open` bucket in the escape arm; serial fallback when `wait -n` is unavailable |
| `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` | Re-pin the `d2` open-PR row to the new `open` bucket; add rows: open-PR note line, merged-PR-missing-push-run still pends, parallel-mode wall row (SLOW fixture converges under `PBG_BUDGET_S` where serial cannot), worker result-file aggregation + missing-result → CANNOT ESTABLISH, `PBG_JOBS` validation rows |
| `scripts/ci-pr-affected-replay.py` | `FOLDED_JOBS` frozenset (~:214, after `ALWAYS_RUN_JOBS`) with header comment naming the two authorities; `suites_failed_in` condition extended to consult it (`folded-job` note) |
| `plugins/soleur/test/ci-pr-affected-replay.test.sh` | Parity row: `sorted(FOLDED_JOBS \ {cla-check,cla-evidence}) == sorted(ci.yml member tokens)`; pin cla names to `required-checks.txt`; disjointness `FOLDED ∩ (ALWAYS_RUN ∪ suites) = ∅`; classification fixture row (failing `rule-body-lint` job → `rule-irrelevant`); mutant row dropping `FOLDED_JOBS` from the condition; `mystery-job` row unchanged |

## Files to Create

None — all edits land in existing files.

## Implementation Phases

#### Phase 1: Thread 2 — folded-job classification (smaller, independent)

1.1 `scripts/ci-pr-affected-replay.py`: add `FOLDED_JOBS = frozenset((...))` immediately after `ALWAYS_RUN_JOBS` (~:214) with the authority comment (ci.yml `member` tokens; `required-checks.txt` CLA rows; mechanism note that a refused merge_group run's job listing exposes posted check names — `cla-check`/`cla-evidence` were observed failing on a refused run, posted by `merge-queue-cla-synthetics.yml`'s failure step).
1.2 `suites_failed_in`: extend the non-suite branch so `name.split(" (")[0] in ALWAYS_RUN_JOBS` becomes `in ALWAYS_RUN_JOBS or in FOLDED_JOBS`; folded names record `note: "folded-job"` (distinct from `always-run-job` for route-histogram auditability; diagnostic field only).
1.3 `plugins/soleur/test/ci-pr-affected-replay.test.sh`: add the four pins listed in Files to Edit (parity to member-token extraction from ci.yml aggregate steps, cla-name pin to `required-checks.txt`, set-disjointness, classification fixture row) + one mutant row (`in FOLDED_JOBS` removed → folded name returns to `unclassified-job` → RED).
1.4 Run `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` — all rows + mutants green.

#### Phase 2: Thread 1 — bounded-parallel reads

2.1 Worker plumbing: `_pbg_pool` runner (bounded `&` workers, `wait -n -p` reap, bash≥5.1 check → serial fallback); `PBG_JOBS` env validation (`^[0-9]+$`, clamp 1-16, default 8); per-unit result files `$WORK/<phase>-<key>`; a `cut` marker convention — any worker's rc-46 lands a `cut` row the parent checks after each phase (`cut_ny "<phase>"`); a missing result file is `CANNOT ESTABLISH` (worker died silently = defect, fail loud — never a skip). **Workers never emit probe output or call `exit` on their terminal paths** — `cut_ny`/`fail_api` exist only in the parent; inside a worker an rc-46 becomes a `cut` row and a read failure a `fail` row in that worker's result file (a worker `exit` would kill only its subshell while its printed verdict line could pollute the parent's output stream).
2.2 Runs-list phase: fetch ≤`PAGE_CAP` pages in one pool wave (page param is independent; short-page rule applied after aggregation in page order).
2.3 Examine loop: parent writes the candidate list (`idx id pr branch hrepo`); worker performs head-lookup → files → machinery filter → jobs read, writes `qual|skip|cut|fail` to `$WORK/exam-<idx>`; parent sorts `qual` rows by `idx`, takes first `MAX_RUNS` → `green_prs`/`green_ids`/`sum_min`/`qwait_*` aggregated in candidate order (bit-identical to serial semantics).
2.4 Artifact phase: stage A parallel per-run listings (`$WORK/arts-<rid>` = aid list or `none`/`fail`/`cut`); parent builds the global download queue honoring `ART_READ_CAP` (listings + downloads counted by construction — no shared counter); stage B parallel downloads → `$WORK/tsv-<rid>-<aid>`; a failed/unparseable member marks the run `run_partial` → `evidence_absent` (unchanged semantics); stage C serial per-run `awk` pricing with the existing cross-artifact `seen[$1]` dedupe.
2.5 Escape loop + pending re-scope: worker per PR writes `$WORK/esc-<pr>` = `dropped|open|pending|ok|escape <detail>` — `state=="closed" && merged_at empty` → `dropped` (unchanged); `state=="open"` → `open` (NEW; covers sha-set and sha-empty open PRs — the `pulls/N` read already carries `state`, no extra read); `state=="closed" && merged_at set` → push-run read → `escape`/`ok`/`pending` (merged-PR pending semantics unchanged); parent prints `note:` lines for `dropped` AND `open`, ESCAPE lines, then the existing `pending > 0` NOT YET arm.
2.6 Run `bash scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` — all rows green including re-pinned `d2` and new parallel rows.

#### Phase 3: Verification + issue bookkeeping

3.1 `bash scripts/test-all.sh` shard legs covering both suites (legible names: `plugins/soleur/test/ci-pr-affected-replay.test.sh`, `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` and `scripts/test-all-pr-battery-gate.test.sh`).
3.2 Post-merge: re-run the probe locally with `PBG_UNBOUNDED=1` — a PASS/FAIL verdict line resolves #9323's measurement arm (recorded as a tracker comment). NOT a PR AC — a post-merge verification the plan names explicitly (it cannot run in CI: live `gh api` + GH_TOKEN).
3.3 PR body: `Closes #12360` + `Refs #9729` (schedule term 1 only — the issue stays open pending the later fresh-window R3 ruling) + `## Changelog` section + semver label expectation `patch`.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Resumable progress across invocations (persist qualifying set + priced runs) | Deferred — buys T1-P1 at far higher cost: no durable substrate exists (sweeper execs probes under `env -i` on ephemeral runners; a state channel would be a new mechanism needing its own design). Revisit trigger: parallel reads still starve inside `PBG_BUDGET_S≤300`. |
| Bound the pending wait per open PR (e.g. only PRs open < N days pend) | Rejected — any positive bound keeps `pending > 0` absorbing at ~30 open PRs; only full exclusion resolves the state. |
| Add the 13 names to `ALWAYS_RUN_JOBS` directly | Rejected — the parity row at `ci-pr-affected-replay.test.sh:646` asserts `ALWAYS_RUN ∪ suite families == ci.yml job keys` exactly; adding non-job names breaks the pin that forces classification of NEW ci.yml jobs. |
| Folded set = all 30 member tokens across 3 umbrella workflows | Descoped (pending CTO ruling) — the merge_group census (`receipts/census-w2.txt`) shows only ci.yml job names + posted cla names reach a ci.yml run's job listing; other workflows' member names were never ci.yml job names. |
| Folded set = all merge_group workflows' job names + posted names | Descoped (pending CTO ruling) — wider than the measured need; `dependency-review`, `quality-guards` etc. never surfaced in the census stem list. |
| Early-exit artifact loop once `evidenced ≥ MIN_RUNS` | Rejected — degrades the mean's evidence base for ~zero wall gain under parallelism. |
| `xargs -P` instead of `&`/`wait -n -p` pool | Rejected — loses the per-call deadline contract inside workers (a fresh `bash -c` child restarts `SECONDS`; `( )`/`&` subshells share it) and the rc-46 → `cut_ny` channel; the repo already proves the `wait -n -p` idiom. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the #9323 soak never converges (issue stays open, measurement arm unresolved) or the S4 re-measurement inherits the same `unclassified-job` inflation — no user-facing artifact; worst concrete harm is delayed CI-cost savings.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — read-only probes over public-repo CI metadata; no secrets beyond the existing `GH_TOKEN` read scope the probe already holds.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** measurement-tooling internals with no user data, no required-check surface and no activation path (S4 stays locked); the blast radius is a wrong verdict on an internal soak, which the honest-NOT-YET contract already bounds.

## Observability

The probe IS the observability instrument; its verdict channel is the sweeper → tracker comment on #9323. This change adds no new surface to observe — it makes an existing one converge.

```yaml
liveness_signal:
  what: "probe verdict line on issue #9323 (PASS/FAIL/NOT YET/CANNOT ESTABLISH) posted per sweeper run"
  cadence: "daily (scheduled-followthrough-sweeper)"
  alert_target: "GitHub issue #9323 tracker comments (sweeper posts per followthrough-convention)"
  configured_in: "issue #9323 <!-- soleur:followthrough script=… earliest=… secrets=GH_TOKEN --> directive"
error_reporting:
  destination: "probe stdout → sweeper log → tracker comment; exit 3 CANNOT ESTABLISH on API-read failure"
  fail_loud: "exit 78 on xtrace-with-token; exit 3 (never a silent verdict) on failed reads; cut rows exit 2 NOT YET"
failure_modes:
  - mode: "verdict starvation (this fix's target)"
    detection: "repeated NOT YET lines on #9323; a PBG_UNBOUNDED=1 local run >300 s"
    alert_route: "issue #12360"
  - mode: "absorbing pending regression"
    detection: "NOT YET: N qualifying PR(s) have no completed push run persisting while the window holds only open/unpushed PRs"
    alert_route: "issue #12360"
  - mode: "job-name drift refills not-evaluable"
    detection: "replay-summary.txt routes histogram shows unclassified-job: entries in the next R3 pass"
    alert_route: "issue #9729 re-measurement"
logs:
  where: "sweeper run log + #9323 comment trail"
  retention: "GHA retention + issue history"
discoverability_test:
  command: "grep -F FOLDED_JOBS scripts/ci-pr-affected-replay.py >/dev/null && grep -F open_prs scripts/followthroughs/pr-battery-gate-saving-9323.sh >/dev/null && printf 'observability-ok'"
  expected_output: "observability-ok"
```

## Guard Contract

### Guard 1 — folded-name parity pin

**Property.** `FOLDED_JOBS` is exactly the union of ci.yml umbrella member tokens and the two CLA posted check names — a folded/unfolded member or a renamed CLA context forces a set edit, never silent drift back into `unclassified-job`.

**Assembly.** Every name that can reach `suites_failed_in`'s non-suite branch (the single chokepoint: `name.split(" (")[0] in ALWAYS_RUN_JOBS or in FOLDED_JOBS`); sources: `.github/workflows/ci.yml` "Aggregate member verdicts" `member <name>` lines (guards-ruleset + guards-advisory), `scripts/required-checks.txt` CLA Required rows (`cla-check`, `cla-evidence`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `rule-body-lint` from `FOLDED_JOBS` | RED (parity row: set ⊋ ci.yml member tokens) |
| 2 | Revert `suites_failed_in` to `in ALWAYS_RUN_JOBS` only (guard's own dispatch: the set exists but is never consulted) | RED (classification row: failing `rule-body-lint` job → `rule-irrelevant`) |
| 3 | Add `member zeta-guard …` to a ci.yml aggregate step without touching `FOLDED_JOBS` (a SECOND member after compliant firsts) | RED (parity row: extracted set has a name the frozenset lacks) |
| 4 | Mutate the test's member-extraction regex to match nothing (harness row: extraction returns empty → parity would pass vacuously if equality were not strict) | RED (non-empty floor on the extracted side of the equality) |
| 5 | Reorder `member` lines in a ci.yml aggregate step (permitted variance — same set, different order) | PASS |

**Anchor.** The pin is structural — the expected side is re-extracted from `ci.yml`/`required-checks.txt` on every suite run, not a stored hash, so no same-commit weakening can satisfy it; `required-checks.txt` is CODEOWNERS-gated per its header.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "parallelize artifact reads and/or resumable progress across invocations" [#12360 fix direction] | Phase 2.1-2.4 (bounded-parallel reads; resumability deferred per Cut List) | mapped |
| 2 | "re-scope the pending definition for open PRs (exclude them from `pending`, or bound the pending wait per PR)" [#12360] | Phase 2.5 (`open` bucket) | mapped |
| 3 | "preserve the exit vocabulary (0/1/2/3/78) and the sweeper-refusal on `SOLEUR_FT_EARLIEST` set-ness" [brief] | AC-5, AC-6; no change to the seam block | mapped |
| 4 | "update `scripts/ci-pr-affected-replay.py`'s job-name classification sets … so refused-run classification no longer drops those jobs into `not-evaluable`" [#9729 schedule term 1] | Phase 1 (`FOLDED_JOBS` + `suites_failed_in` + parity rows) | mapped |
| 5 | "a third R3 ruling pass on a fresh 300-commit window happens LATER — NOT in this PR" [brief] | Non-Goals | mapped |
| 6 | "Stage 4 stays non-activated: `CI_PR_AFFECTED` unset, `PR_AFFECTED_LOCKED` intact, merge_group keeps the full battery" [brief] | Non-Goals + AC-9 | mapped |
| 7 | "re-run the probe locally with `PBG_UNBOUNDED=1` — a PASS/FAIL verdict resolves #9323's measurement arm" [brief] | Phase 3.2 (post-merge verification) | mapped |
| 8 | "retire it — an operator call" [#12360 alternative] | — | descoped — justification: the issue itself frames retirement as an operator call; the fix removes the starvation that motivated it |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `FOLDED_JOBS` frozenset + `suites_failed_in` consult | "update `scripts/ci-pr-affected-replay.py`'s job-name classification sets" | asked |
| New `folded-job` note label | — | inferred — justification: route-histogram auditability needs to distinguish folded names from live always-run jobs; diagnostic field, zero contract impact |
| Parity pin to `member` tokens + `required-checks.txt` | "note the parity test that pins the set to ci.yml" [brief] | asked |
| Bounded-parallel worker pool (`&` + `wait -n -p`) | "parallelize artifact reads" | asked |
| `open` bucket in escape arm | "exclude them from `pending`" | asked |
| `PBG_JOBS` env knob (default 8) | — | inferred — justification: a tunable concurrency bound is needed to keep the sweeper's ~1000-req/hr token budget and GitHub secondary-rate-limit posture honest; carries a default so the `env -i` sweeper contract is unchanged |
| bash≥5.1 serial fallback | — | inferred — justification: `wait -n -p` needs bash 5.1; the repo's own scheduler (`test-all.sh:2230`) serial-degrades rather than failing — the probe must keep producing NOT YET, never crash, on an old bash |
| Parallel runs-page prefetch | — | inferred — justification: same property T1-P1 buys; page params are independent and the read count is bounded by `PAGE_CAP` either way |
| Test row re-pins/additions | "Fix directions … parallelize … re-scope" | asked |

### Split Assessment

- Subsystems touched: 2 — `scripts/` (first-segment), `plugins/soleur/test/` → `plugins/` (first-segment)
- Planned files: 4 | Estimated changed lines: ~250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — all under
- Recommendation: single PR (matches the operator's "combining is acceptable" pre-approval)

## Acceptance Criteria

- [ ] **AC-1** `FOLDED_JOBS` exists in `scripts/ci-pr-affected-replay.py` as a frozenset of exactly the 11 ci.yml member tokens + `cla-check` + `cla-evidence`, consulted by `suites_failed_in` so a failing non-suite job named by it records `note: "folded-job"` and never sets `ne`.
- [ ] **AC-2** Parity: `sorted(FOLDED_JOBS \ {cla-check,cla-evidence}) == sorted(<member tokens extracted from .github/workflows/ci.yml aggregate steps>)`, plus `cla-check` and `cla-evidence` greppable as whole lines in `scripts/required-checks.txt`, plus `FOLDED_JOBS ∩ (ALWAYS_RUN_JOBS ∪ {suite families}) = ∅` — all asserted in `plugins/soleur/test/ci-pr-affected-replay.test.sh`.
- [ ] **AC-3** A refused-run fixture whose only failing job is `rule-body-lint` (or any member name) classes `rule-irrelevant`, while `mystery-job` still classes `not-evaluable` (`unclassified-job:` route preserved).
- [ ] **AC-4** The probe completes a fixture sweep with the SLOW marker under `PBG_BUDGET_S=270` where the serial implementation could not (wall-deadline NOT YET) — demonstrating T1-P1.
- [ ] **AC-5** Exit vocabulary unchanged: 0/1/2/3/78 mean exactly what the header documents; every pre-existing test row (`s1`-`s9`, `b1`-`b9`, `c1`-`c4`, `pg1`, `h1`, `d1`, `q1`, `e1`, `m11`, `dx`, `t1`, `n1`, `w1`, `u0`-`u2`) still passes except `d2`, which is re-pinned (AC-7).
- [ ] **AC-6** `PBG_UNBOUNDED=1` + `SOLEUR_FT_EARLIEST` set (even empty) still exits 3 "operator-local only"; `PBG_BUDGET_S` validation unchanged on the budgeted path.
- [ ] **AC-7** An open qualifying PR lands in the new `open` bucket — excluded from `pending` and `escapes`, with a `note:` line mirroring the `dropped` arm; a CLOSED-MERGED qualifying PR whose push run is absent/incomplete still lands `pending` → exit 2; a closed-unmerged PR still lands `dropped`.
- [ ] **AC-8** `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` and `bash scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` exit 0 (all rows + mutants + assertion floors).
- [ ] **AC-9** Non-activation: the diff contains no edit to `.github/workflows/*.yml`, `scripts/ci-pr-selection.sh`, `scripts/required-checks.txt` (content lines), `scripts/ci-required-ruleset-canonical-required-status-checks.json`, `infra/**`, or `scripts/suite-shard-legs.tsv`/`scripts/suite-durations.tsv`/`scripts/test-all.sh` registrations.
- [ ] **AC-10** Every `gh api` read the probe issues still flows through `api()`/`api_bin()` (the `min(60, END-SECONDS-5)` cap); a deadline cut in ANY worker still surfaces as `NOT YET: … wall deadline …` (exit 2), never a partial-evidence verdict.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (sequential-fallback — cto role Assess interface run inline; plugin subagents unavailable on this harness surface)
**Assessment:** Two measurement-tool fixes, medium complexity. Highest risks: (a) shared-state accumulation under `&` workers — resolved by per-unit result files aggregated in the parent (subshell writes do not propagate); (b) the rc-46/cut_ny channel must survive parallelism — a deadline cut in any worker aborts the phase as NOT YET; (c) `SECONDS` semantics — verified bash `( )`/`&` subshells share the parent epoch, so `api()`/`api_bin()` are worker-safe unchanged; (d) the pending re-scope loses the "open PR later merges red" signal — accepted residual, identical in kind to the already-accepted `dropped` arm; (e) `FOLDED_JOBS` self-validates via parity pins per the fail-open-allowlist learning. No new substrate, no DB writes (read-only API), no architectural decision — `soleur:architecture create` not recommended. Capability gaps: none.

### Product/UX Gate

Product domain not flagged; mechanical UI-surface override checked all Files to Edit — no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx` or ui-surface terms. Tier: NONE — skipped.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (94 issues) bodies grepped for all four Files-to-Edit paths plus `ci-pr-affected`/`battery-gate`/`12360`/`9729` terms: zero matches.

## Test Scenarios

| # | Layer | Scenario | Expected |
|---|---|---|---|
| 1 | unit | Fixture: refused run failing only `rule-body-lint` (member name) | `rule-irrelevant`, never `not-evaluable` |
| 2 | unit | Fixture: refused run failing `mystery-job` | `not-evaluable` / `unclassified-job:` (T2-P2 honesty) |
| 3 | unit | Parity: remove `rule-body-lint` from `FOLDED_JOBS` | parity row RED |
| 4 | unit | Mutant: drop `in FOLDED_JOBS` from `suites_failed_in` | classification row RED |
| 5 | unit | Open qualifying PR (state=open, any sha) | `open` bucket + note; `pending==0`; verdict reachable |
| 6 | unit | Closed-merged qualifying PR, push run absent | `pending` → exit 2 NOT YET |
| 7 | unit | Closed-unmerged qualifying PR | `dropped` (unchanged) |
| 8 | integration | SLOW fixture, `PBG_BUDGET_S=270`, parallel default | converges to a verdict-path exit where serial exits 2 |
| 9 | integration | Worker killed without writing a result file | `CANNOT ESTABLISH` exit 3 — never silent evidence |
| 10 | integration | `PBG_UNBOUNDED=1` + `SOLEUR_FT_EARLIEST=` | exit 3 "operator-local only" |
| 11 | integration | bash without `wait -n -p` | serial fallback, same verdict, no crash |
| 12 | unit | `PBG_JOBS=abc` | CANNOT ESTABLISH (validation), `PBG_JOBS=99` clamps to 16 |

## Success Metrics

- `PBG_UNBOUNDED=1 bash scripts/followthroughs/pr-battery-gate-saving-9323.sh` produces a verdict line (`PASS`/`FAIL`) in a single local run — measured post-merge (Phase 3.2).
- Next R3 ruling pass on a fresh window shows zero `unclassified-job:` routes among post-fold job names in `replay-summary.txt`.
- Sweeper-path probe run exits 0/1 within `FT_PROBE_TIMEOUT=300` (verifies the parallel path suffices under the real kill).

## Dependencies & Risks

- **Merge-order race with PR #12377** — disjoint hunks confirmed; whichever lands second rebases; their test changes re-key the fake-gh fixture map (`fx_err`/`keyof`), so a second-landing version of this PR re-keys its new fixtures to match.
- **`gh api` secondary rate limits under concurrency** — bounded by `PBG_JOBS≤16` (default 8); a 403 still surfaces CANNOT ESTABLISH as today.
- **`green_prs` over-admission under parallel examine** — prevented by post-aggregation ordering: qualify all, sort by candidate index, take first `MAX_RUNS` (serial-identical outcome).
- **Worker-result loss** — missing result file → CANNOT ESTABLISH (fail loud, never partial evidence).
- **Open-PR residual** — a qualifying PR open at verdict time that later merges with a red push run is an escape the retired probe never sees; accepted (the alternative never converges; main-side red is separately paged by `notify-main-failure`).

## Non-Goals

- Re-running the R3 ruling on a fresh 300-commit window (later, per schedule term 2).
- Any activation path: `CI_PR_AFFECTED` stays unset, `PR_AFFECTED_LOCKED` intact, `merge_group` keeps the full battery.
- A cancelled-run policy for `unsettled-jobs:` not-evaluable routes (schedule term 1 names only the allowlist).
- Resumable probe state across sweeper invocations (deferred, trigger documented).
- Edits or comments on PR #12377 (explicit brief constraint).
- A `version` key in any plugin manifest; CHANGELOG file edits (changelog rides the PR body per release convention).

## References & Research

See `## Research Insights` — premise validation, property list, cut list, measured basis, repo research, institutional learnings, related issues/PRs.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

