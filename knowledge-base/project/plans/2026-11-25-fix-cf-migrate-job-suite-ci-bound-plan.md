---
title: "fix: cf-account-migrate-job.test.sh outgrew its 720 s CI bound, and its trap turns the kill into false failures"
date: 2026-11-25
slug: fix-cf-migrate-job-suite-ci-bound
branch: feat-one-shot-13051-cf-migrate-test-bound
issue: 13051
closes: 13051
type: fix
priority: p1
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

## Enhancement Summary

**Deepened on:** 2026-11-25
**Sections enhanced:** 5 (Research Insights, Technical Approach Phase 1 and Phase 3, Dependencies & Risks, a new Network-Outage Deep-Dive)
**Checks run:** deepen-plan halt gates 4.6-4.13 (all pass); live state of 14 cited issues and PRs; a
parent/child repro of the trap semantics; a dry run and a scratch `--write` simulation of the infra
manifest regen; a verify-the-negative sweep; a self-audit for symbols the plan review cut.

### Key Improvements

1. The trap fix and its self-test are now proven by a runnable repro (Phase 1, "Research Insights
   (deepen)"). The new trap returns rc 143 in 3 ms with no resume and the sandbox gone. Today's trap
   returns rc 0 and prints the resume marker and a FAIL row, both under a process-group TERM and under
   the real `timeout`.
2. The regen's real behaviour was measured. A dry run over today's committed table already moves 9
   suites with no input change (weight drift). Seeding this suite at 400000 ms moves 11, and the
   sticky packing puts this suite on leg 2 beside `ci-deploy` and `git-data-wipe-assert`, not on leg 3.
   Phase 3 now says to expect that and record it.
3. The committed weights predict about 2000 s of suite time per leg. Observed leg 1 summed 3165 s on
   the failing main run. Other suites' weights are stale, so predicted leg balance is not observed leg
   balance. That stays a Non-Goal with a follow-up, now with numbers.

### New Considerations Discovered

- The regen warns `13 registered label(s) have no measured timing — tabled at floor 4000ms`. With
  `--durations`, floor rows stay at the floor. The "require `0 at floor`" learning applies to
  `--timings-dir` regens, not to this one.
- The network-outage keyword gate fired on the word `timeout`. Here it names the coreutils bounder,
  not a network symptom (see the Network-Outage Deep-Dive section).

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The CF account-migration job battery (`apps/web-platform/infra/cf-account-migrate-job.test.sh`) now runs
longer than its per-suite bound on a contended CI leg. When the runner's `timeout` sends SIGTERM, the
suite's trap deletes the sandbox and lets the script keep going, so every later case reports a false
FAIL. This plan makes the trap end the run on a signal, measures and records the suite's CI duration,
rebalances the infra shard legs, and makes the battery itself faster so it fits well inside its bound.

## Research Insights

### Premise Validation

- #13051 is OPEN with an empty body; its title is the spec. #12931 (epic) is OPEN. The collision
  pre-check hit only PR #13052, which is this branch's own WIP draft, so no foreign duplicate exists.
- The bound line exists on this branch as claimed: `apps/web-platform/infra/run-registered-suites.sh`,
  the `_SUITE_BOUNDS` entry `"apps/web-platform/infra/cf-account-migrate-job.test.sh=720"` (the last
  entry of the map). Its comment still says "its weight row is 106 s measured", which is stale.
- The trap defect exists as claimed: `apps/web-platform/infra/cf-account-migrate-job.test.sh`,
  `trap 'rm -rf "$SBX"' EXIT INT TERM HUP` right after `SBX="$(mktemp -d -t cf-migrate-job.XXXXXXXX)"`.
  On TERM, bash runs the handler, deletes the sandbox, and then RESUMES the script. Every later case
  then fails on a missing path.
- The "32 false failures" claim holds. On main push run 45382769432, job 138406100761 (leg 1/4), the RED
  relay shows `rc=124 elapsed=720s start_offset=+348s`, and after the kill FAIL rows such as
  `R4a ... check is RED on the base (WHY=rc:)` follow `mktemp: failed to create directory via template
  '/var/tmp/soleur-run.../cf-migrate-job.wUxdbhDE/runs/tfhost-base.XXXXXX': No such file or directory`.
- The leg ceiling is 20 minutes, not 15. `.github/workflows/infra-validation.yml` job
  `deploy-script-tests` sets `timeout-minutes: 20` (raised by #12091). It runs 4 legs
  (`leg: ["1/4", "2/4", "3/4", "4/4"]`), each running the runner at `-P min(nproc,6)` = 4.

### Measured CI duration of this suite (suite-timings-infra-* artifacts, `gh run download -p`)

| Run | Event / branch | Suite ms | Verdict |
|---|---|---|---|
| 44850654502 | push main (pre-#13019) | 198000 | PASS |
| 44974359237 | PR (pre-#13019) | 197000 | PASS |
| 45089704823 | PR | 361000 | PASS |
| 45135051391 | PR #13019 branch | 322000 | PASS |
| 45288054979 | PR #13019 branch | 488000 | PASS |
| 45297557350 | PR #13019 branch | 721000 | FAIL (bound) |
| 45305377374 | PR #13019 branch | 548000 | PASS |
| 45310047029 | PR #13019 branch | 545000 | PASS |
| 45382769432 | push main, merge of #13019 (2ed71c9f1e) | 720000 | FAIL (bound) |

The committed weight `apps/web-platform/infra/suite-durations.tsv` row is `106000 measured`
(generated 2026-11-20), so heavy-first dispatch (#11568) ranks the suite behind its leg-mates and
starts it late (`start_offset=+348s` on the failing main leg). A local serial run on 2026-11-25
(16-core dev host, with a profiling job running beside it for part of the run) printed
`cf-account-migrate-job: 285 passed, 0 failed (285 cases)` in `real 15m48s, user 6m45s, sys 8m42s`.
The suite is serial, so it used one core. The high `sys` share shows the cost is process spawning.
The archived #13019 plan recorded 585 s on a quieter run. Section starts in that run, in seconds:
inputs 1, ids 17, preflight 23, rehearsal 33, apply 39, entrypoint 79, hardening 86, re-dispatch 120,
import-normalize 132, mutations about 300, end 947. The stall row F7e alone took about 48 s.

Leg wall times (job start to completion) over the same runs: leg 1 612-1112 s, leg 2 536-921 s,
leg 3 349-568 s (lightest every time), leg 4 687-817 s. Leg 1 also carries
`web-host-provisioner-parity-mutation` (318-593 s), `infra-config-repush-mutation` (277-509 s) and
`git-data-wipe-assert` (233-403 s), so four heavy suites share 4 slots on it. On the failing main run,
leg 1's suites summed to 3165 s against 1200-2513 s on the other legs.

Leg 4's failure on the same main run is a different suite (`cloud-init-inngest-bootstrap.test.sh`,
the vinngest pin lag tracked by #12506). It is out of scope here.

### Where a job run's time goes (measured with an xtrace of a scratch copy of the SUT)

- About 330 job runs per suite run: 108 `red` rows (2 runs each), 3 `green_mut`, 54 `norm_row`, about
  54 inline `new_case ...; run_job ...; verdict` rows, plus the small loops.
- A plain redirects-dns apply job takes about 2.1 s. An import-normalize (`norm_case`) job takes about
  2.9 s. An input-refusal job takes about 30 ms. `new_case` takes about 20 ms.
- About 1.3 s of the plain 2.1 s is the SUT's in-flight check, as measured under xtrace (which inflates
  fork-heavy loops). `gated_workflows` greps every one of the 111 files under the real
  `.github/workflows/` and runs a fixed-point loop, because `run_job` passes `GITHUB_WORKSPACE="$REPO"`
  (xtrace: about 0.94 s). `refuse_inflight` then makes N_GATED x 5 `gh` stub calls (xtrace: about
  0.38 s). Kieran's review re-timed `gated_workflows` without xtrace: 0.60 s over the real tree and
  0.047 s over a mirror of the gated files.
- The live record read (26 stubbed GETs, each a bash stub plus one `jq` over `plan.json`) costs about
  0.4 s per read. A norm apply job reads twice (52 GETs).
- One row sleeps for real: `setup_norm_stall` makes the doppler stub `exec sleep 40` under the job's
  outer read deadline.

### Relevant files

- `apps/web-platform/infra/cf-account-migrate-job.test.sh`: the suite (1894 lines,
  `EXPECTED_CASES=285`). Its row helpers are `new_case`, `run_job`, `red`, `green_mut`, `norm_row` and
  `verdict`. The anti-vacuity floor and the PASS+FAIL=CASES identity sit at the end. The "Stub
  refusals" row scans every `$SBX/runs/*/` dir whose `script` is the pristine copy.
- `apps/web-platform/infra/scripts/cf-account-migrate-job.sh`: the SUT. It refuses to run under xtrace
  (exit 78, #7797) and reads `$GITHUB_WORKSPACE/{.github/workflows,tests/scripts/lib,apps/web-platform/infra/scripts}`.
  It writes only under `$RUNNER_TEMP/cf-migrate`, and the stubs write only under `$STUB_DIR` (the case
  dir). Concurrent job runs therefore share no writable path.
- `apps/web-platform/infra/run-registered-suites.sh`: `_SUITE_BOUNDS`, the `timeout -k 30 <bound>`
  wrapper, the heavy-first dispatch that reads `suite-durations.tsv`, and the manifest assignment that
  reads `suite-shard-legs.tsv`.
- `apps/web-platform/infra/suite-durations.tsv` and `apps/web-platform/infra/suite-shard-legs.tsv`
  (`# n=4`): the committed weights and the leg table. Both are written by
  `scripts/regenerate-shard-manifest.py --group infra`, and their label sets must match
  (`.github/scripts/test/test-infra-suite-registration.sh`, durations-table coherence).
- `scripts/test-all-corpus-weight-budget.test.sh`: `CORPUS_SUITE_CAP_MS=600000`. Any committed weight
  over 600 s needs a `scripts/suite-weight-exemptions.tsv` row, so the recorded weight must stay under
  it.
- Precedent for in-suite parallelism: `apps/web-platform/infra/workspaces-luks-provision.test.sh`
  (`MAXJ="${WLP_MUT_JOBS:-3}"`, `throttle() { while [ "$(jobs -rp | wc -l)" -ge "$MAXJ" ]; do wait -n; done; }`,
  rows scored in row order). Its comment records that 6 concurrent mutants "starved sibling suites into
  their per-suite bounds on a 4-vCPU CI leg (run 36917791726)". `betterstack-alert-structure.test.sh`
  uses up to 6 concurrent mutants.

### Institutional learnings

- `knowledge-base/project/learnings/2026-05-12-pgid-inheritance-and-bash-trap-defer-on-foreground-commands.md`:
  bash runs a TERM trap only after the foreground child returns. GNU `timeout` signals its whole process
  group, so the job child is terminated too. A trap that waits in `wait` (the pool) runs at once.
  Children are stopped with `kill` on `jobs -p`, never `kill 0`, so the signal does not reach the parent.
- `knowledge-base/project/learnings/2026-10-18-a-bound-sized-from-one-contended-sample-was-1-12x-not-1-35x.md`:
  size a bound from several runs' worst observed, at least 1.5x, and check it against the enclosing leg
  ceiling.
- `knowledge-base/project/learnings/workflow-patterns/2026-10-31-shard-reprice-checkpoint-mechanics.md`:
  re-price one row by seeding the committed table (`--durations seed.tsv`), not by a full
  `--timings-dir --write`. Download artifacts with `-p` (glob).
- `knowledge-base/project/learnings/2026-10-03-a-manifest-priced-from-staged-runs-misses-a-suite-that-landed-after-them.md`:
  re-list the newest runs right before `--write`, and require `0 at floor` in the dry run.
- `knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md` and
  `2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md`:
  sharing fixtures or reusing base runs can make a mutant hit a short-circuit instead of the mechanism.
  Each mutant must still run its own job.
- `knowledge-base/project/learnings/2026-10-09-committed-ci-weights-are-not-local-costs.md`: measure
  on the machine that pays (the CI leg), not locally.

### Related issues and PRs

- PR #12958 (draft, branch `feat-one-shot-12937-zot-bridge-handshake`, not touched here) adds 258 lines
  to the suite: a `[tunnel]` section of inline rows and `red` rows, a mirror workspace `MT` built from
  symlinks, and `GITHUB_WORKSPACE` set through `env.extra`. It is based on a pre-#13019 main
  (`EXPECTED_CASES=172` -> `210`), so it must rebase anyway. The helper signatures below stay unchanged,
  so that rebase stays mechanical.
- PR #12995 (open, bastion runcmd rehearsal) edits `run-registered-suites.sh` (+78 -15) and
  `infra-validation.yml`. Conflict risk is limited to the `_SUITE_BOUNDS` map region and the manifest
  rows. Whichever PR merges second re-runs the manifest regen.
- #12506: the leg-4 `cloud-init-inngest-bootstrap` failure on the same main run.
- 17 other infra suites (18 trap lines) carry the same non-exiting `trap '...' EXIT INT TERM HUP`
  shape (`grep -nE "^\s*trap .*(INT|TERM)" apps/web-platform/infra/*.test.sh | grep -v exit` prints
  19 lines, one of them this suite). They are tracked in #13055, filed during this planning run.

### Community and functional overlap

No uncovered stack (bash and GitHub Actions are covered). `soleur:engineering:discovery:functional-discovery`
found three partial registry matches (a Jest/pytest test orchestrator, a CI sharding writer, a
project-specific async runner). None targets bash batteries, so there is nothing to install.

### Property List (Phase 0.6b)

- P1: when the suite receives SIGTERM, SIGINT or SIGHUP, it stops running cases, prints one line saying
  the run was cut short, removes its sandbox, and exits non-zero without printing further PASS/FAIL rows.
- P2: the suite's CI duration is measured from CI artifacts and written down where the scheduler and
  the reader both see it (the weight row and the bound's comment).
- P3: the infra legs are rebalanced from a measured weight for this suite (the regen decides the leg).
- P4: the suite's CI duration sits well inside its bound, and the bound sits below the leg ceiling, by
  making the battery do less work or run it concurrently, not only by widening the bound.
- P5: every guard row the suite carries today still runs and still discriminates (the 285-case floor
  and each mutant's own job run are preserved).

### Cut List (Phase 0.6b)

- "Only raising the bound" -> P4 -> rejected by the brief itself. The bound stays at 720 (CTO ruling).
- Memoizing identical base runs across `red` rows -> P4 -> lever (b) below already removes most of
  the per-job cost. Memoizing would tie rows to each other through the `RED_BASE` chains for about
  80 s (CTO ruling).
- A per-case record-body cache in the curl stub -> P4 -> it changes the stub's pre/post
  `recfilter`/`reccode` behaviour for about 0.5 s per norm job (CTO ruling).
- A runner-level annotation of post-TERM output (for all suites) -> P1 -> the in-suite trap covers P1
  for this suite. The 17 sibling suites are tracked in #13055 (see Non-Goals), not built here.
- A new standalone suite file for the trap test -> P1 -> an in-suite self-test covers it without a new
  registered suite, manifest rows or a weight row.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| The suite "outgrew its 720 s CI bound" | True. 720000/721000 ms bound-kills on runs 45382769432 and 45297557350, and 488-548 s passes beside them | Speed the battery up (Phases 2-3) and keep the bound at 720 |
| "its trap turns the kill into 32 false failures" | True. The trap removes `$SBX` and returns, and later rows fail on missing paths | Phase 1 |
| The archived #13019 plan recorded "172 passed, 585 s" | 172 was the case count before #13019 finished. The file now pins `EXPECTED_CASES=285` | Every count in this plan is re-measured |
| The brief says to rebalance "the shard legs" against "the leg ceiling" | The ceiling is 20 min (1200 s), not the 15 min that several comments in `run-registered-suites.sh` still cite | Measure against 1200 s and leave those other comments alone |
| The weight row says the suite takes 106 s | Stale. It measures 322-548 s on CI since #13019 | Phase 4 re-prices it from this PR's CI runs |

## Problem Statement

Three defects compound:

1. **A signal does not end the run.** `trap 'rm -rf "$SBX"' EXIT INT TERM HUP` cleans up and then lets
   bash resume. The runner kills at the bound with `timeout -k 30 720`, which signals the whole process
   group. The job child dies, the parent's handler deletes the sandbox, and the remaining rows run
   against nothing. The RED relay then shows about 32 FAIL rows that are artifacts of the kill. They
   hide which rows actually ran and make the failure read like a regression.
2. **The battery is slow and serial.** About 330 job runs at about 2-3 s each, one after another. More
   than half of each plain job is the SUT re-deriving the gated workflow set from all 111 real workflow
   files. That work is identical in every row except the `[inflight]` rows, which exist to test it.
3. **The scheduler prices the suite at 106 s.** So the suite sits on leg 1 beside the three other
   heaviest suites, and heavy-first dispatch starts it last (`start_offset=+348s`).

## Proposed Solution

Each item is a CTO ruling recorded in
`knowledge-base/project/specs/feat-one-shot-13051-cf-migrate-test-bound/decision-challenges.md`. The
plan review (DHH, Kieran, code-simplicity, CTO devex lens, and a strong-model advisor) reshaped the
first draft. The CTO re-ruled the sequencing on 2026-11-25 (see "Plan Review Revisions").

Delivery is **two steps in one PR, with a measurement gate between them**:

- **Step A (always):** the signal trap, the slim workspace (lever b), the F7e stall cut, the
  re-price and the regen.
- **Step B (only if Step A's CI measurement of this suite is over 360 s):** a bounded row pool
  (lever a), designed below but not built unless the gate trips.

### Step A

1. **Signal traps that exit.** The EXIT trap cleans only. TERM, INT and HUP get one handler that
   prints `[ABORTED] signal <SIG> after <CASES> case(s); this run is void, not a verdict` to stderr
   and exits `128+n` (143, 130, 129). The `exit` runs the EXIT trap, so the sandbox is still removed.
   `run_job` keeps running the job in the foreground. Under the runner's `timeout`, the whole process
   group gets TERM, so the job child dies at once and the deferred trap runs right after it. A
   `bash "$2" & wait $!` form is rejected: in non-interactive bash an async command starts with SIGINT
   and SIGQUIT ignored and stdin on `/dev/null`, which would change the SUT's INT handling
   (`cf-account-migrate-job.sh` relies on INT for the apply deadline). A TERM sent to the parent alone
   therefore waits for the current job (about 3 s), which is acceptable. An in-suite self-test proves
   the handler with the same process-group TERM that `timeout` sends, and AC3 checks the real
   `timeout` once on the full suite.
2. **A slim default workspace (lever b).** At startup the suite builds `$SBX/ws-slim` in the same way
   as the existing `MIRROR_WF`: `tests` and `apps` symlinked to the repo, and `.github/workflows/`
   holding one symlink per file of the suite's own pre-exempt reach set, derived from the real tree at
   startup. Every other `.github` entry is symlinked through as well, so the SUT sees the real
   `.github` minus the workflows it does not need. `run_job` defaults `GITHUB_WORKSPACE` to that
   mirror. `env.extra` still wins because it comes later in the `env` argv. The existing `$MIRROR`
   (used by about 16 re-dispatch rows) links `$MIRROR/.github` to `ws-slim/.github` instead of
   `$REPO/.github`. The `[inflight]` section's inline rows keep the real tree: after their setup, the
   suite appends `GITHUB_WORKSPACE=$REPO` to that case's `env.extra` (the append comes after setup, so
   a setup that overwrites `env.extra` cannot drop it). A new parity row asserts that the job over the
   slim mirror reports `inflight=none workflows=${N_GATED}`, the same count as the real-tree
   derivation.
3. **The F7e stall cut.** The doppler stub's `exec sleep 40` (the `mode.doppler_stall` seam) becomes
   `exec sleep 12`, with the inequality written as a comment on that line. The stall is used only by
   `setup_norm_stall` in the F7e row. Both of its runs use the F7S/F7T mutants, which set
   `LIVE_READ_DEADLINE=8`. `chk_norm_stall` reads `calls.log`, `timeout.log` and the refusal, not
   the duration. `12 > 8` keeps the stall outlasting the read deadline. This saves about 30 s.
4. **Bound and weight.** The bound stays at 720 s, below the 1200 s leg ceiling minus the 30 s `-k`
   grace. The weight row in `suite-durations.tsv` is re-priced from this PR's CI runs, and the leg table
   is regenerated with `regenerate-shard-manifest.py --group infra --durations` (dry run first). The
   suite is not moved by hand.
5. **An authoring contract in the file.** The suite's `# HARNESS` header gains the rules a row author
   needs: the default workspace is slim and which rows need the real tree, setups write only under
   `$LAST_D`, how to keep the sandbox for debugging (`CFAM_KEEP_SBX=1`, which skips the `rm` and prints
   the path), and how to re-measure. `fail()` prints which workspace the failing job ran against,
   beside `rc=`.

### Expected effect of Step A (to be confirmed by measurement)

Two measurements disagree, and the gate exists because of that:

- The xtrace split of a plain job put the 111-file scan at about 0.94 s and the N_GATED x 5 `gh` stub
  loop at about 0.38 s. xtrace inflates fork-heavy loops.
- Kieran's review timed the SUT's `gated_workflows` in a scratch copy, without xtrace, on an idle host:
  0.60 s over the 111 real files and 0.047 s over a mirror of the gated files. That is about 0.55 s
  saved per job, roughly 150 s serial, not 250 s.

So Step A saves roughly 150-250 s from lever (b), about 15 s from the `$MIRROR` repoint and about
30 s from F7e. Against the CTO's 620 s baseline that lands at 325-425 s. **Step B is therefore
likely to be needed.** The gate still stands: it costs one push, and it keeps the pool out of the PR
if Step A suffices. Before pushing Step A, re-measure the plain-job saving locally without xtrace (one
plain apply job, before and after the slim mirror, `date +%s%N` around `run_job`) and record both
numbers in the PR body. If Step A and Step B together still miss 360 s, AC4 says stop and re-plan.
The next lever would be the `gh` stub loop (35 `timeout` + bash + `grep` spawns per job), which is a
new technical fork for the CTO, not something to add silently.

### Step B (built only if the gate trips)

A bounded pool of whole rows, as the advisor proposed and the CTO ruled:

- `red`, `green_mut` and `norm_row` keep their signatures. Their setups still run in the parent,
  serially, in source order.
- Each row's existing body (`run_job`, the check, `verdict`) then runs in one background subshell
  that writes its PASS/FAIL lines and its counter deltas to a file in the row's dir. `LAST_D` and
  `WHY` are correct inside the subshell with no restore logic, and `red`'s "skip the mutant when the
  base is RED" short-circuit survives.
- `_pool_flush` waits for every queued row (a full drain, not one `wait -n`), prints the files in
  registration order, and adds up the deltas. Inside a row subshell `verdict` writes to the row file
  and never flushes.
- Up to `CFAM_MUT_JOBS` rows run at once (default 3, an integer 1-8, otherwise exit 2), throttled with
  `wait -n` as in `workspaces-luks-provision.test.sh`.
- The public `run_job` flushes the queue first, so an inline row never runs beside pooled jobs. A row
  whose case dir has an `env.extra` line matching `^SECONDS=` runs in the foreground. That decision
  reads the case dir after setup, so rows added later (#12958) inherit it.
- A flush runs before "Stub refusals", and the section headers become a `section` helper that
  flushes. Only Step B touches the headers.
- The handler then also kills the pool's row subshells and their children. Each row runs in its own
  process group, and the handler kills the group. A pool-mode self-test sends `kill -TERM <pid>` to
  the child directly (not through `timeout`, which would kill the group by itself), waits for an
  `armed` line first, and checks `kill -0` against the fixture's own recorded innermost PIDs.

## Technical Approach

### Research Insights (deepen): the trap semantics, reproduced

A 20-line parent/child pair in the session scratchpad reproduced both sides before any AC was committed
to text. That follows the deepen-plan rule for process-group and trap ACs, and
`knowledge-base/project/learnings/2026-05-12-pgid-inheritance-and-bash-trap-defer-on-foreground-commands.md`.
The child installs the trap, prints `armed`, runs `bash -c 'sleep 30'` in the foreground, then prints
`SIGTEST-RESUMED` and a FAIL row. The parent starts it with `set -m; bash child.sh & pid=$!; set +m`,
waits for `armed`, and runs `kill -TERM -- -$pid`.

| Trap | Delivery | rc | Time to exit | `[ABORTED]` | Resumed | Sandbox |
|---|---|---|---|---|---|---|
| New (EXIT cleans; TERM handler exits 143) | process-group TERM | 143 | 3 ms | 1 | 0 | removed |
| Today's (`rm -rf` on EXIT INT TERM HUP) | process-group TERM | 0 | 4 ms | 0 | 1 | removed |
| New | `timeout -s TERM -k 5 2` | 124 | 2 s | 1 | 0 | removed |
| Today's | `timeout -s TERM -k 5 2` | 124 | 2 s | 0 | 1, plus 1 FAIL row | removed |

The last row is #13051 in miniature. The group signal kills the foreground `sleep` at once, so the
deferred trap runs immediately and the self-test costs milliseconds, not the fixture's 30 s. The
discriminator is the resume marker (and rc 143 vs 0 under a direct group kill), not the sandbox. The
old trap also removes the sandbox, so Guard 1 row 2 is a separate mutation (an EXIT trap that no longer
cleans), not a property of the old trap.

The precedent-diff for the trap shape is novel in this directory. None of the 18 sibling trap lines
the survey found (17 suites) is a precedent for the exiting shape, and #13055 will use this suite's shape as
the template.

### Phase 1 — Signal handling (tests first)

1. Write the self-test before changing the trap, and confirm it goes RED against today's trap (Guard 1
   row 1).
2. Self-test. The suite prints `[sandbox] <path>` to stderr right after `mktemp`, on every run (it
   also serves `CFAM_KEEP_SBX`). Right after the trap registration and before the instrument self-test,
   `derive_gated` and any fixture build, a seam check reads `CFAM_JOB_SIGTEST`. When it is set, the
   child builds only the stubs it needs, prints `SIGTEST armed` to stderr, and runs one foreground
   `run_job` whose script is a fixture that sleeps 30 s. After that `run_job` it prints
   `SIGTEST-RESUMED` and `verdict 1 "SIGTEST row after the signal"`. It reaches that point only if the
   handler returned.

   The parent reproduces what the runner's `timeout` does, without its timing race. It starts the
   child as its own process group (`set -m; bash "$SELF" & pid=$!; set +m`; `set -m` is portable where
   `setsid` is not), waits for the `armed` line with a bounded poll (at most 20 s, failing the row if
   it never appears), then sends `kill -TERM -- -$pid` to the whole group, exactly as `timeout` does
   without `--foreground`. It asserts:
   - rc 143;
   - exactly one `[ABORTED] signal TERM` line on stderr;
   - no `SIGTEST-RESUMED` and no `^  FAIL: SIGTEST` line on stdout;
   - the exact path from the child's `[sandbox]` line no longer exists.

   The child's setup time no longer matters, because the signal is sent only after `armed`. AC3 then
   checks the real `timeout` once, on the full suite.
3. Replace the trap line as in Step A item 1.
4. Bump `EXPECTED_CASES` by the self-test verdicts added.

### Phase 2 — Slim workspace and the stall cut (lever b)

1. (As built: `derive_gated` takes an optional third argument that writes the reach set; no separate
   `derive_reach` function.) Add `derive_reach` (the pre-exempt reach set) beside `derive_gated`, and leave `GATED_FILE`
   byte-identical.
2. Build `$SBX/ws-slim` from it (Step A item 2). An empty mirror, or one whose workflow count differs
   from `|reach|`, exits 2 as `[FATAL]` before any row runs.
3. `run_job`: `GITHUB_WORKSPACE="$WS_DEFAULT"`, with `WS_DEFAULT="$SBX/ws-slim"`. Record the value in
   the case dir (`workspace`) so `fail()` can print it.
4. Point `$MIRROR/.github` at `ws-slim/.github`.
5. For the `[inflight]` section's inline rows, append `GITHUB_WORKSPACE=$REPO` to `env.extra` after
   setup. Confirm no mutant row needs the real tree:
   `grep -nE "mk_mutant [a-z0-9-]+ .*(LOADER_RE|CALLEE_RE|gated_workflows|refuse_inflight|LIVE_STATUSES|grew)" apps/web-platform/infra/cf-account-migrate-job.test.sh`
   finds V19 and V20 today, and both already run on `MIRROR_WF` through `setup_inflight_caller`.
6. Add the parity row (Guard 2).
7. The stall cut (Step A item 3).
8. `CFAM_KEEP_SBX=1` and the `# HARNESS` header contract (Step A item 5).

### Phase 3 — Measure, gate, record, rebalance

1. Push. From the PR's infra-validation run, read the suite's row in its leg's
   `suite-timings-infra-*` artifact (`gh run download <id> -p 'suite-timings-infra-*'`). Repeat on at
   least one more push. Use the worst figure.
2. **Gate.** If the worst figure is over 360000 ms, build Step B (Phase 4), push, and re-measure. If it
   is at most 360000 ms, skip Phase 4 and record that the gate passed in the PR body.
3. Edit only this suite's row of `apps/web-platform/infra/suite-durations.tsv`, setting it to the final
   worst figure in ms (`measured`).
4. `python3 scripts/regenerate-shard-manifest.py --group infra --durations apps/web-platform/infra/suite-durations.tsv`
   as a dry run. Measured during deepen: over today's unchanged table the dry run already reports
   `vs incumbent: 9 moved` (drift in the committed weights). A scratch `--write` with this suite seeded
   at 400000 ms (`--manifest`/`--durations-out` pointed at scratch copies) reported `11 moved` and put
   this suite on leg 2 beside `ci-deploy.test.sh` and `git-data-wipe-assert.test.sh`, with
   `web-host-provisioner-parity-mutation` and `infra-config-repush-mutation` on leg 1. Expect a similar
   outcome and record it; the other suites' moves come from their own stale weights, not from this
   change. Paste the predicted per-leg totals into the PR body. Then add `--write --allow-growth`.
   The committed-weight drift gate (#11662) refuses a row that grows past 1.5x and 10 s, and 106000 ms
   to about 300000+ ms is such a growth. `--allow-growth` records a `# growth-acked=` header line.
   State why in the PR body: the old weight predates #13019's import-normalize section. The `--write`
   also rewrites the tables' `generated-*` header lines. Commit the manifest and the durations table
   together.
5. Rewrite the comment on the `_SUITE_BOUNDS` entry. Give the post-fix worst CI figure, the ratio
   720 / worst (target at least 2x) and this PR's number, which links to the full run table in the PR
   body. Also give the re-measure recipe (the download command, the single-row edit, and the
   `--durations` dry-run-then-`--write` steps). Add the revisit triggers: lower the bound after five
   post-fix CI samples, and re-price when `EXPECTED_CASES` grows by more than about 10% (#12958 will).
6. Re-run the legs after the regen, and record each leg's wall time in the PR body. Record it, do not
   gate on it.

### Phase 4 — Row pool (Step B, only if the Phase 3 gate trips)

1. Write the pool-mode self-test first. It goes RED against a handler that kills no pool child.
2. Build the pool as in "Step B" above, then extend Guard 1 with the pool rows and add Guard 3.
3. Capture the golden label list from the Step A commit's serial run before writing the pool:
   `grep -oE '^  (PASS|FAIL): .*' stepA.log | sed 's/ (WHY=.*//' > golden.txt`. After the pool lands,
   the default run must pass and
   `diff golden.txt <(grep -oE '^  (PASS|FAIL): .*' pooled.log | sed 's/ (WHY=.*//')` must print
   nothing, except the pool's own self-test rows, which are listed in the PR body. Record the commands
   and file names in the PR body.
4. Return to Phase 3 step 1.

## Files to Edit

- `apps/web-platform/infra/cf-account-migrate-job.test.sh`: trap, self-test, slim workspace and
  `$MIRROR` repoint, `[inflight]` real-tree appends, parity row, stall cut, `CFAM_KEEP_SBX`, `fail()`
  workspace line, `# HARNESS` contract, `EXPECTED_CASES`. Step B only: the pool and the `section`
  helper.
- `apps/web-platform/infra/run-registered-suites.sh`: the comment on the
  `cf-account-migrate-job.test.sh=720` entry only. The value stays 720.
- `apps/web-platform/infra/suite-durations.tsv`: this suite's row, re-priced from CI.
- `apps/web-platform/infra/suite-shard-legs.tsv`: regenerated by
  `regenerate-shard-manifest.py --group infra --durations ... --write`.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt`: the row for
  `apps/web-platform/infra/cf-account-migrate-job.test.sh` (currently `130`) moves with the edit.
  Regenerate it with `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline` in the
  same commit. The baseline is row-by-row equality, so check that only this row changed.
- `.claude/hooks/grep-q-pipe-guard.test.sh`: only if that guard reds on a new `| grep`, `| curl` or
  `| doppler` pipe in the suite. It carries three exempt rows for this file. Prefer code that adds no
  new verb pipe.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-13051-cf-migrate-test-bound/decision-challenges.md`:
  the ruling table.

## Non-Goals

- The 17 sibling suites with the same trap shape. Tracked in #13055, with a proposed ratchet sentinel.
- The leg-4 `cloud-init-inngest-bootstrap.test.sh` failure on the same main run (#12506).
- Lowering the 720 s bound. Revisit after five post-fix CI samples (CTO ruling). The bound's comment
  records that trigger.
- Re-pricing the other suites on leg 1, whose committed weights date from 2026-11-20. If the dry-run
  leg table still puts this suite beside all three of `web-host-provisioner-parity-mutation`,
  `infra-config-repush-mutation` and `git-data-wipe-assert`, record it in the PR body and file a
  re-price follow-up. Do not pin a leg by hand.
- Any change to the SUT `apps/web-platform/infra/scripts/cf-account-migrate-job.sh` or to the gate
  library.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Raise the bound to 900-1080 s | Rejected. The brief rules it out, and the suite would still sit on the heaviest leg |
| Build the job pool unconditionally | Superseded by the CTO re-ruling: the pool is about 60% of the new code, sits on the #12958 rebase surface, and its gain on a contended -P 4 leg is unmeasured. It is built only if the Step A measurement misses 360 s |
| A job-level queue with deferred scoring (first draft) | Rejected by the CTO for Step B in favour of whole-row subshells: the job-level queue needed `LAST_D`/`WHY` restores, captured `RED_BASE`, and dropped `red`'s base-RED short-circuit |
| `bash "$2" & wait $!` in `run_job`, so a parent-only TERM is handled at once | Rejected by the CTO: an async command in non-interactive bash ignores SIGINT and reads `/dev/null`, which changes the SUT's INT semantics |
| A pool-mode self-test under `timeout` | Rejected: `timeout` signals the whole group, so the test cannot fail. Step B uses a direct `kill -TERM` instead |
| Memoize identical base runs across `red` rows (lever c) | Rejected by the CTO: ties rows together through `RED_BASE` chains for about 80 s |
| Cache record bodies in the curl stub (lever d) | Rejected by the CTO: changes `recfilter`/`reccode` pre/post semantics for about 0.5 s per norm job |
| Split the suite into two registered files | Rejected. It adds manifest, weight and registration rows, breaks the shared fixtures (`D_REH`, `D_AP`, mutants) and makes the #12958 rebase harder |
| Pin the suite to leg 3 by hand | Rejected by the CTO: lost at the next regen |
| A standalone suite file for the trap test | Rejected by the CTO: needs manifest rows for no extra coverage |

## Open Code-Review Overlap

2 open code-review issues mention `run-registered-suites.sh`: #8890 (review of the #8763
deploy-script-tests K=4 matrix) and #8487 (capability-gate corpus follow-ups, runner log reaping).
Acknowledge both: their concerns (matrix design, decline-evidence retention) are not touched by a
comment-only edit to one `_SUITE_BOUNDS` entry. No open code-review issue names the suite,
`suite-durations.tsv` or `suite-shard-legs.tsv`.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. This is CI test machinery. The
  operator gets a red or flaky `deploy-script-tests` leg that blocks infra PRs. Worse, a green leg
  could hide migration-job guards that silently stopped discriminating. The CF account migration
  (#12931) would then ship its next phase with weaker refusal coverage.
- **If this leaks, the user's data is exposed via:** no new exposure. The suite uses synthesized
  fixtures and the `SENTINEL-SECRET-VALUE-DO-NOT-PRINT` value only. The slim workspace symlinks
  tracked repo files. No token value is printed, and the SUT's xtrace refusal is untouched.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change edits a test harness and CI scheduling data, and
  touches no user-facing or credential path.
- `threshold: none, reason: the touched apps/web-platform/infra/ files are a test battery, its bound comment and the CI shard tables; none runs on a host or handles user data.`

## Observability

```yaml
liveness_signal:
  what: the runner's per-suite line for this suite on its deploy-script-tests leg (PASS or RED, with rc and elapsed) plus the suite-timings-infra-N artifact row
  cadence: per infra-validation run (every PR and push touching the infra paths)
  alert_target: the PR's check view and the ::error annotation the runner emits on RED
  configured_in: .github/workflows/infra-validation.yml (deploy-script-tests, Run registered infra suites step) and apps/web-platform/infra/run-registered-suites.sh
error_reporting:
  destination: GitHub Actions job log and annotations; no Sentry surface (CI-only code)
  fail_loud: the runner's RED line for apps/web-platform/infra/cf-account-migrate-job.test.sh with rc and elapsed, and on a kill one "[ABORTED] signal TERM after N case(s)" line instead of cascaded FAIL rows
failure_modes:
  - mode: the suite is bound-killed again (rc=124)
    detection: the runner's RED line names the suite and the bound; the [ABORTED] line says how many cases ran
    alert_route: the PR author, through the failed check
  - mode: a row stops running or is counted twice
    detection: the EXPECTED_CASES floor and the PASS+FAIL=CASES identity exit 1 with a [VACUITY] line
    alert_route: the PR author, through the failed check
  - mode: the slim workspace drifts from the real gated set
    detection: the Guard 2 parity row reds, naming both counts; an empty or short mirror exits 2 as [FATAL]
    alert_route: the PR author, through the failed check
  - mode: a failing job ran against the slim workspace when it needed the real tree
    detection: fail() prints the job's workspace beside rc=
    alert_route: the PR author, through the failed check
logs:
  where: the deploy-script-tests leg log, and the infra-suite-logs-N artifact on a failed leg
  retention: 14 days (retention-days in infra-validation.yml)
discoverability_test:
  command: grep -o -m1 cf-account-migrate-job.test.sh=720 apps/web-platform/infra/run-registered-suites.sh
  expected_output: "cf-account-migrate-job.test.sh=720"
```

## Guard Contract

### Guard 1 — a signal ends the run

**Property.** After the suite receives TERM, INT or HUP, it prints no further PASS/FAIL row, removes
its sandbox, and exits non-zero.

**Assembly.** The trap registrations at the top of the suite (EXIT, plus the one handler bound to
TERM, INT and HUP), and the places a signal can land: a foreground `run_job`, where the handler runs
only after the child exits. In Step B there is also the pool's `wait -n`. The self-test drives the
foreground path with a process-group TERM (what `timeout` sends), after an `armed` line. AC3 drives
the real `timeout` once against the full suite.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore today's `trap 'rm -rf "$SBX"' EXIT INT TERM HUP` | RED: `SIGTEST-RESUMED` and a FAIL row appear after the signal |
| 2 | The handler exits but the EXIT trap no longer removes `$SBX` | RED: the printed sandbox path still exists |
| 3 | The child never prints `armed` (the guard's own dispatch: the parent would otherwise signal nothing and assert on an empty run) | RED: the bounded poll times out and the row fails, never passes |
| 4 | Step B only: the handler kills no pool child. Each pool job records the SUT's own PID; the pool-mode child is sent `kill -TERM <pid>` to the suite alone, not to its group | RED: `kill -0` succeeds for a recorded SUT PID |

**Harness rows.** Point the self-test parent at the wrong child output file: the assertions must
then fail on a missing `[ABORTED]` line, not pass on an empty file.

### Guard 2 — slim workspace parity

**Property.** The job, run over the slim default workspace, derives the same gated workflow set as the
suite's independent derivation over the real tree.

**Assembly.** `derive_reach` and `derive_gated` over `$REPO/.github/workflows`, the `ws-slim`
construction, `run_job`'s `WS_DEFAULT`, the `$MIRROR` repoint, and the `[inflight]` rows' real-tree
appends.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Build `ws-slim` from the post-exempt `GATED_FILE` instead of the pre-exempt reach set | RED: the `[FATAL]` size check compares the mirror's file count with `|reach|`, and the exempt list holds loader-using workflows (`cf-account-migrate.yml`, `scheduled-terraform-drift.yml`, ...), so `|reach| > |gated|`. The parity count alone would stay GREEN on today's tree, because no caller reaches the loader only through an exempt file |
| 2 | Drop one reach file from `ws-slim` | RED: the parity row's `workflows=` count differs |
| 3 | `ws-slim` is empty (the guard's own dispatch) | RED: `[FATAL]` exit 2 before any row |

**Harness rows.** A must-PASS non-canonical input: add an extra non-gated symlink to `ws-slim`;
parity must still hold. V19 must still go RED against its mutant through `MIRROR_WF`. M9
(`inflight-exempt-drift`) and J4 (`live-statuses`) also mutate the derivation and run on the slim
mirror; they stay discriminating because the mirror holds the full pre-exempt reach set, exempt files
included.

### Guard 3 — pooled rows are scored faithfully (Step B only)

**Property.** Every pooled row is scored exactly once, in registration order, from its own subshell's
output, after its own job finished. No setup writes outside its own `$LAST_D`.

**Assembly.** `_pool_flush` and its full drain, the per-row output files, the delta summation, the
`run_job` pre-flush, the `^SECONDS=` foreground rule, and the anti-vacuity floor. The handler kills
the recorded SUT PIDs with TERM and then waits, because `$!` names the row subshell, not the SUT under
it, and a background job ignores SIGINT. Shared-state
integrity: a listing of `$SBX/bin` and of the top level of `$SBX` taken at the first enqueue, compared
with one taken at the final flush.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | The flush drains with one `wait -n` instead of all jobs | RED: rows read unfinished files; the floor or the label diff fails |
| 2 | Drop the flush before "Stub refusals" | RED: the floor counts fewer cases |
| 3 | The flush prints only the first row file (a second member after a compliant first) | RED: `[VACUITY]` case count |
| 4 | A setup writes a file at the top level of `$SBX` | RED: the closing listing comparison |
| 5 | Inline `run_job` stops flushing first | RED: the pooled run's label list differs from the golden list |

**Harness rows.** The golden list is the ordered verdict labels of the Step A serial suite, captured at
the Step A commit before the pool lands. Comparing `CFAM_MUT_JOBS=1` with the default cannot catch a
missing flush, because both defer scoring the same way. The pooled run must match the golden list.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "the suite's trap must exit on a signal (SIGTERM/SIGINT) instead of continuing and reporting cascaded false failures" | Phase 1, Guard 1 | mapped |
| 2 | "record the suite's measured CI duration" | Research Insights run table; Phase 3 steps 1, 3 and 5 (`suite-durations.tsv` row, bound comment) | mapped |
| 3 | "rebalance the shard legs" | Phase 3 step 4 (`suite-shard-legs.tsv` regen) | mapped |
| 4 | "bring the suite well inside a bound below the leg ceiling (speed up the battery, e.g. parallelize or cut redundant setup, rather than only raising the bound)" | Phase 2 (cut redundant setup: slim workspace, stall cut), Phase 3 gate, Phase 4 (parallelize, if needed), AC4 | mapped |
| 5 | "never print token values, no SSH" | User-Brand Impact, AC9; no token or SSH step anywhere in the plan | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `cf-account-migrate-job.test.sh` edits | asks 1, 4 | asked |
| `run-registered-suites.sh` comment | ask 2 | asked |
| `suite-durations.tsv` row | ask 2 | asked |
| `suite-shard-legs.tsv` regen | ask 3 | asked |
| `fixture-relative-assert.baseline.txt` row | — | inferred — justification: the baseline is row-by-row equality over this file, so editing the suite reds that guard unless the row moves in the same commit |
| `decision-challenges.md` | — | inferred — justification: the brief's technical-ruling instruction requires every ruling to be persisted there |
| `CFAM_KEEP_SBX`, the `fail()` workspace line, the `# HARNESS` contract | — | inferred — justification: the slim default workspace changes where a failing job ran, so a row author needs to see it and keep the sandbox to debug it (CTO devex review) |
| Guards 2-3 | — | inferred — justification: the slim workspace (and the pool, if built) change how 285 guard rows execute, so the rows' integrity needs its own guard (P5) |
| #13055 (filed, not built) | — | inferred — justification: deferral tracking for the 17 sibling suites the audit found |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `plugins/soleur`, `knowledge-base`
- Planned files: 7 | Estimated changed lines: ~180 for Step A, ~350 with Step B
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [x] AC1: `bash apps/web-platform/infra/cf-account-migrate-job.test.sh` exits 0 and prints
  `cf-account-migrate-job: <N> passed, 0 failed (<N> cases)`, where N = 285 plus the verdicts this PR
  adds, and `EXPECTED_CASES` equals N.
- [x] AC2: Guard 1 mutation rows 1, 2 and 3 (and row 4 if Step B is built), each applied to a scratch
  copy of the suite, make that copy exit 1 with the named self-test row RED. The PR body records the
  command used for each.
- [x] AC3: Killing a real run mid-battery shows the fix.
  `timeout -s TERM -k 30 60 bash apps/web-platform/infra/cf-account-migrate-job.test.sh` exits 124.
  Stderr carries exactly one `[ABORTED] signal TERM` line. Stdout has no `FAIL:` row other than the
  instrument self-test's deliberate `FAIL arm records (EXPECTED, subtracted below)` line. The exact
  path printed on the run's `[sandbox]` stderr line is gone (`mktemp -t` follows `TMPDIR`, so never
  glob for it). Recorded once in the PR body as evidence.
- [ ] AC4: The suite's `suite-timings-infra-*` value over at least three infra-validation attempts of
  this PR's final commit has a worst of at most 480000 ms and a median of at most 360000 ms, and the
  row is PASS. The bound stays at 720 s. (Second revision 2026-11-25, CTO review-phase ruling: the median
  clause is dropped, because with the pool off on CI the median measured the CPU the pool took from
  the leg's other suites; the worst <= 480000 ms clause stands. Revised 2026-11-25 by CTO ruling after Steps A and B missed
  the original 360000 ms worst-of-2 on runner-wide 2x variance; see decision-challenges.md. The
  original wording: worst of at least two runs at most 360000 ms; if both steps miss, stop and re-plan.)
- [x] AC5: If Step B is built, the pooled run's ordered verdict labels equal the Step A golden list
  (the Phase 4 step 3 diff prints nothing beyond the listed pool self-test rows), and the run passes. If Step B is not built,
  `grep -c 'CFAM_MUT_JOBS' apps/web-platform/infra/cf-account-migrate-job.test.sh` prints `0`.
- [ ] AC6: `apps/web-platform/infra/suite-durations.tsv` carries this suite at the AC4 worst figure, in
  ms, marked `measured`, and that is the only changed data row in the file. Header lines (`#`) may
  change. `git diff origin/main -- apps/web-platform/infra/suite-durations.tsv | grep -cE '^\+[^#+]'`
  prints `1`. (Revised 2026-11-25, CTO review-phase ruling: `ci-deploy.test.sh` and
  `cron-egress-nftables.test.sh` are re-priced to their worst measured CI figures, 878000 and 483000,
  so the leg balance does not rest on known-stale weights; the grep prints `3`. This suite's row starts
  at the 396000 serial Step A figure and moves to the AC4 worst only if that is more than 10% above it.)
- [x] AC7: `suite-shard-legs.tsv` was produced by
  `regenerate-shard-manifest.py --group infra --durations apps/web-platform/infra/suite-durations.tsv --write`,
  and the dry-run leg table is in the PR body. The leg this suite lands on is recorded, whatever it is.
- [ ] AC8: The `_SUITE_BOUNDS` entry still reads `cf-account-migrate-job.test.sh=720`. Its comment
  names the weight row's basis (revised 2026-11-25: commits after the AC4 measurement may not touch
  this file, so the measured attempts live in the PR body), the ratio, the PR number, the re-measure recipe and both revisit
  triggers. Check with
  `grep -B12 'cf-account-migrate-job.test.sh=720' apps/web-platform/infra/run-registered-suites.sh | grep -cE 'suite-timings-infra|--durations|five post-fix|EXPECTED_CASES'`,
  which prints at least `4`.
- [x] AC9: No line the suite adds prints a token value or runs `ssh`.
  `git diff origin/main -- apps/web-platform/infra/cf-account-migrate-job.test.sh | grep -cE '^\+.*(\bssh |echo .*TF_VAR_cf_api_token)'`
  prints `0`.
- [ ] AC10: These all exit 0: `bash .github/scripts/test/test-infra-suite-registration.sh`,
  `bash scripts/test-all-corpus-weight-budget.test.sh`,
  `bash plugins/soleur/test/fixture-relative-assert.test.sh`,
  `bash .claude/hooks/grep-q-pipe-guard.test.sh`,
  `bash apps/web-platform/infra/run-registered-suites.test.sh`, and `bash scripts/test-all.sh --affected`.
  (Status 2026-11-25 on c684ba1f9d: the five named suites exit 0. `--affected` exits 1 on suites this
  diff does not reach: `cloud-init-strip-helpers-mutation` is red on main too (#12850),
  `test-trio-baseline-census` passes alone (its A3 row saw a probe file another suite wrote mid-run),
  and the web-platform likec4 sandbox rows are outside the diff.)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. The change touches a CI test
battery and its scheduling tables. No user-facing page, copy, pricing, legal surface or data
processing changes.

## Test Scenarios

| # | Scenario | Expected |
|---|---|---|
| T1 | Full run | 0 failed, N cases |
| T2 | Self-test: process-group TERM after `armed` | rc 143, one `[ABORTED]`, no `SIGTEST-RESUMED`, the printed sandbox gone |
| T3 | Ctrl-C (INT) during a local run | rc 130, one `[ABORTED] signal INT` line |
| T4 | Slim parity row | `inflight=none workflows=${N_GATED}` over the slim mirror |
| T5 | `[inflight]` "reads every gated workflow x 5 statuses" row | Still PASS, run against `$REPO` |
| T6 | F7e with the 12 s stall | RED as required (`WHY=no-outer-timeout`), in about 12 s instead of about 48 s |
| T7 | `CFAM_KEEP_SBX=1` | The sandbox path is printed and still exists after the run |
| T8 | AC3: kill a real run mid-battery | Exit 124, no cascaded FAIL rows |
| T9 | Step B only: pool-mode child sent `kill -TERM <pid>` (the suite alone) after `armed` | rc 143, `kill -0` fails for every recorded SUT PID |
| T10 | Step B only: pooled run versus the Step A golden label list | The same ordered labels |

## Dependencies & Risks

- **The SECONDS rows have about 40 s of margin.** The s760/s840 rows assume one job takes well under
  40 s. Step A adds no concurrency, so this is unchanged. In Step B they run in the foreground.
- **Step B is likely.** The estimate for Step A alone is 325-425 s against a 360 s gate. AC4 takes the
  worst of at least two runs, so a lucky run cannot skip Step B.
- **#12958 rebase.** Its rows call `new_case`/`run_job`/`verdict` inline and use `red`. Step A changes
  none of those signatures. Its tunnel cases set `GITHUB_WORKSPACE=$MT` through `env.extra`, which
  still wins. Its `MT` mirror links `$REPO/.github` and could point at `ws-slim/.github` as well. Its
  `EXPECTED_CASES` must be re-derived. If Step B is built, its `printf '\n[tunnel]...'` header should
  become a `section` call.
- **#12995** edits `run-registered-suites.sh` and `infra-validation.yml`. Whichever lands second
  re-runs the manifest regen dry run and re-checks the `_SUITE_BOUNDS` region.

## Network-Outage Deep-Dive

The deepen-plan keyword gate fired on `timeout`. In this plan the word names the coreutils per-suite
bounder (`timeout -k 30 720` in `run-registered-suites.sh`), not a network symptom. No layer applies:

| Layer | Status |
|---|---|
| L3 firewall allow-list | Not applicable. The suite makes no network call; `curl`, `gh`, `doppler` and `aws` are PATH stubs |
| L3 DNS / routing | Not applicable, for the same reason |
| L7 TLS / proxy | Not applicable. The curl stub refuses any argv it does not model |
| L7 application | Not applicable. No SSH and no live service anywhere in the plan |

## Plan Review Revisions

Applied from the 2026-11-25 panel (DHH, Kieran, code-simplicity, CTO devex lens, opus advisor), with
the CTO re-ruling where a technical fork was re-opened:

- The pool moved behind a measurement gate (DHH, simplicity; CTO re-ruling A).
- If built, the pool queues whole rows in subshells, not job runs (advisor; CTO re-ruling B).
- `run_job` stays in the foreground (advisor proposal rejected; CTO re-ruling C).
- The pool-mode self-test under `timeout` was cut because it cannot fail. Step B tests the pool with a
  direct `kill -TERM` and an `armed` line instead (advisor, simplicity).
- Lever (b)'s saving was corrected from about 1.3 s to about 0.9 s per job from the xtrace split
  (DHH).
- New cheap cuts: the F7e stall from 40 s to 12 s (DHH; CTO verified), and `$MIRROR/.github` pointed
  at the slim mirror (DHH).
- `real_tree` as a general helper was cut, because no mutant needs it. The `[inflight]` inline rows
  append the real tree after setup instead (DHH, CTO devex).
- Guard 4 (the SECONDS marker scan) was cut, Guard 3's self-referential row was dropped, and the
  setup-writes-only-under-`$LAST_D` condition became part of Guard 3 (simplicity, CTO devex).
- AC7 now records the leg the regen picks instead of asserting a leg the plan cannot force. The leg
  wall times are recorded, not gated (DHH, simplicity).
- Kieran: the regen needs `--allow-growth` and rewrites header lines, so AC6 counts data rows only; the
  self-test signals the child's process group after an `armed` line instead of racing a fixed
  `timeout`; the sandbox path is printed and asserted exactly; FAIL checks anchor on `SIGTEST`; Step
  B's order check uses a golden list from Step A, because `CFAM_MUT_JOBS=1` defers scoring too; the
  handler kills recorded SUT PIDs; Guard 2 row 1 is caught by the size check, not the parity count;
  lever (b)'s saving was re-measured at about 0.55 s per job without xtrace, which makes Step B
  likely.
- The bound comment cites the PR instead of carrying the full run table, and gains the re-measure
  recipe and revisit triggers (simplicity, CTO devex).
- `CFAM_KEEP_SBX`, the `fail()` workspace line and the `# HARNESS` authoring contract were added (CTO
  devex).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.
- The SUT refuses to run under xtrace (`exit 78`, #7797). Profile only a scratch copy with that guard
  removed, never the committed file.
- The self-test needs a `timeout` binary. Resolve it as the runner does (`timeout`, then `gtimeout`,
  or `SOLEUR_TIMEOUT_BIN` when the runner exported it). With neither on PATH, fail under CI (`CI` or
  `GITHUB_ACTIONS` set) and otherwise skip loudly with a counted SKIP line (stock macOS has no
  `timeout`), so a skip is never a silent pass.
- Step B's `wait -n` needs bash 4.3 or later. Add an explicit `BASH_VERSINFO` check that exits 2 with
  a named message.
- (As built: the handler and the EXIT trap reap from the shell's own job table, TERM each job's process
  group, and poll the group empty; no PID list is kept.) In Step B, identify pool children by recorded PIDs and process groups. A pattern-matching process
  search from inside the Bash tool matches its own wrapper's command line.
- `discoverability_test.command` must contain none of `|;&<>$` or a backtick (preflight Check 10's
  shell-active reject); the declared grep satisfies that.
- This plan applied `plan-sharp-edges.md` as a targeted pass (grep over its ~290 entries for traps,
  timeouts, ACs, measurements, manifests and baselines). The file is 265 KB and was not read in full in
  this session.
